import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	deleteInvoiceSchema,
	updateInvoiceDetailsSchema
} from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { updateInvoiceError } from '$lib/server/invoices/errors';
import { organizationFormatting } from '$lib/server/requests/timezone';

// One invoice in full for the detail screen. It reads `public.invoice_detail`, the definer twin of the list's
// read model: it carries the frozen document and the derived contract status worked out once in the database,
// and — behind the same invoices.view_price gate the list uses — the money. The client's account balance
// rides along in one more gated call (`client_account_balance`), so the rail can show what the customer owes
// across all their bills without the browser adding anything up. Permissions are resolved here from the
// caller's access, the same way the Job detail does, so the page knows which actions to offer.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const invoiceId = event.params.id;
	const canSeePrice = hasPermission(check.access, 'invoices.view_price');

	const { data: detail, error } = await supabase.rpc('invoice_detail', {
		target_organization_id: organizationId,
		target_invoice_id: invoiceId
	});
	if (error) {
		if (error.code === 'P0404') return notFound('That invoice could not be found.');
		return databaseError();
	}
	if (!detail) return notFound('That invoice could not be found.');

	const document = detail as {
		invoice: { client_id: string | null };
		[key: string]: unknown;
	};

	// The client's whole-account balance, gated in the same call: a reader without invoices.view_price gets an
	// empty map and the rail simply shows no balance. Only one client is asked for, so this is a single row.
	const clientId = document.invoice.client_id;
	const [balanceResult, formatting] = await Promise.all([
		canSeePrice && clientId
			? supabase.rpc('client_account_balance', { target_client_ids: [clientId] })
			: Promise.resolve({ data: {} as Record<string, unknown>, error: null }),
		organizationFormatting(supabase, organizationId)
	]);
	if (balanceResult.error) return databaseError();
	const balances = (balanceResult.data ?? {}) as Record<string, unknown>;
	const clientBalance = clientId ? (balances[clientId] ?? null) : null;

	return json(
		{
			...document,
			client_balance: clientBalance,
			locale: formatting.ok ? formatting.formatting.locale : 'en-US',
			can_edit: hasPermission(check.access, 'invoices.edit'),
			can_send: hasPermission(check.access, 'invoices.send'),
			can_delete: hasPermission(check.access, 'invoices.delete'),
			can_see_price: canSeePrice,
			can_manage_taxes: hasPermission(check.access, 'settings.taxes.manage')
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Editing a draft's subject, invoice date and terms. The command checks invoices.edit itself and refuses a
// stale revision, so the route only proves membership and validates the shape.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateInvoiceDetailsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('update_invoice_details', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		expected_revision: input.expected_revision,
		new_subject: input.subject,
		new_issue_date: input.issue_date,
		new_payment_term_id: input.payment_term_id,
		new_custom_due_date: input.custom_due_date
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};

// Deleting a draft. The command checks invoices.delete, refuses anything issued, settled, still holding
// money, or already replaced, and uses the idempotency key so a retried delete returns the first result.
export const DELETE: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = deleteInvoiceSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('delete_invoice_draft', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		expected_revision: input.expected_revision,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
