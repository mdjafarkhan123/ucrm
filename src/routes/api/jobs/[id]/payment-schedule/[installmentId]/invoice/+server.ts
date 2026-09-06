import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { createInstallmentInvoiceSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { createInvoiceError } from '$lib/server/invoices/errors';

// Billing one payment-schedule stage (Part 5c-3). `create_installment_invoice` prices the stage, locks its
// amount, splits it across the job's lines and creates the Draft in one transaction — this route only proves
// membership, the same way `/api/invoices` POST does for a direct invoice; the command checks `invoices.create`
// (and the job's own tenancy) itself, so no separate permission check is made here.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = createInstallmentInvoiceSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('create_installment_invoice', {
		target_organization_id: auth.organization.id,
		target_job_id: input.job_id,
		target_installment_id: input.installment_id,
		new_subject: input.subject,
		new_service_property_ids: input.service_property_ids,
		new_payment_term_id: input.payment_term_id,
		new_custom_due_date: input.custom_due_date,
		new_issue_date: input.issue_date,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return createInvoiceError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
