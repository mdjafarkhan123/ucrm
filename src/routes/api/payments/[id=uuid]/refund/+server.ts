import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { refundPaymentSchema } from '$lib/server/validation/invoices.schema';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Paid-launch-trust Part 11: sending money back on this recorded payment. `id` is the payment_event id
// (matches GET /api/payments/[id=uuid]) and this route always refunds the payment on screen, never a quote
// deposit -- refunding a deposit is out of scope, since void already resolves those on its own.
// refund_client_payment (3b-2) re-checks everything else: it caps the amount against what this receipt still
// has left unspent and unrefunded, so this route repeats none of that arithmetic. Gated on
// invoices.correct_payment, same as unapply and move -- recording a payment and correcting one are different
// permissions.
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

	const parsed = refundPaymentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const { data, error } = await event.locals.supabase.rpc('refund_client_payment', {
		target_organization_id: check.auth.organization.id,
		target_payment_event_id: event.params.id,
		target_deposit_event_id: null,
		new_amount_minor: input.amount_minor,
		new_method: input.method,
		new_refund_date: input.refund_date,
		new_reference: input.reference,
		new_note: input.note,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
