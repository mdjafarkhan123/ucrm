import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { recordInvoicePaymentSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Collect Payment. No new database command: record_client_payment records the receipt and applies it in one
// transaction across whatever allocation list it is handed. Without a list the whole amount goes to the invoice
// in the URL (the original single-bill shape); with one, the payment is spread across the client's bills as
// staff entered it and the rest stays as client credit (D8). The command re-checks every bill's client,
// currency and balance, so this route repeats none of that.
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

	const parsed = recordInvoicePaymentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const { data, error } = await event.locals.supabase.rpc('record_client_payment', {
		target_organization_id: auth.organization.id,
		target_client_id: input.client_id,
		new_amount_minor: input.amount_minor,
		new_method: input.method,
		new_payment_date: input.payment_date,
		new_reference: input.reference,
		new_note: input.note,
		new_allocations: input.allocations ?? [
			{ invoice_id: event.params.id, amount_minor: input.amount_minor }
		],
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
