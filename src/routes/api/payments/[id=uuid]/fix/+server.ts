import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { fixPaymentSchema } from '$lib/server/validation/invoices.schema';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Fix payment (D7, Xero's model): the mistyped payment is taken off its bills and reversed, and the corrected
// one is recorded and applied as entered — one transaction in correct_client_payment, which also refuses a
// payment with a live refund, an online (Stripe) payment, and one already corrected. Same permission as the
// other correction moves.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.correct_payment');
	if ('response' in check) return check.response;

	const limited = await enforceOrganizationWriteRateLimit(
		event.locals.supabase,
		check.auth.organization.id,
		'payments'
	);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fixPaymentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const { data, error } = await event.locals.supabase.rpc('correct_client_payment', {
		target_organization_id: check.auth.organization.id,
		target_payment_event_id: event.params.id,
		new_amount_minor: input.amount_minor,
		new_method: input.method,
		new_payment_date: input.payment_date,
		new_reference: input.reference,
		new_note: input.note,
		new_allocations: input.allocations,
		new_reason: input.reason,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
