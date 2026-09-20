import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	applyInvoiceCreditSchema,
	invoiceCreditQuerySchema
} from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// "Add deposit" on one invoice: the money this invoice's client has already given that still has some left
// (GET), and putting some of it on this bill (POST). Both are thin over the database: client_spendable_credit
// lists what is left on each payment or quote deposit, and apply_client_payment (built and pgTAP-tested in
// 3b-1) applies it, re-checking client, currency, what the money has left and what the bill still owes. Both
// commands check invoices.record_payment and invoice price access themselves, so this route repeats neither.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsed = invoiceCreditQuerySchema.safeParse({
		client_id: event.url.searchParams.get('client_id')
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('client_spendable_credit', {
		target_organization_id: auth.organization.id,
		target_client_id: parsed.data.client_id
	});
	if (error) return updateInvoiceError(error);

	return json({ items: data ?? [] }, { headers: NO_STORE_HEADERS });
};

export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const limited = await enforceOrganizationWriteRateLimit(
		event.locals.supabase,
		auth.organization.id,
		'invoices'
	);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = applyInvoiceCreditSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const { data, error } = await event.locals.supabase.rpc('apply_client_payment', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		target_payment_event_id: input.source === 'payment' ? input.source_id : null,
		target_deposit_event_id: input.source === 'deposit' ? input.source_id : null,
		new_amount_minor: input.amount_minor,
		new_reason: null,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});
	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
