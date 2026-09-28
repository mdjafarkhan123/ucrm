import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { withdrawPaymentSchema } from '$lib/server/validation/invoices.schema';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Mark as never received (D7): withdraw_client_payment takes the payment off every bill it is on and appends
// its reversing row in one step, so the bills owe that money again. The original stays in history.
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

	const parsed = withdrawPaymentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const { data, error } = await event.locals.supabase.rpc('withdraw_client_payment', {
		target_organization_id: check.auth.organization.id,
		target_payment_event_id: event.params.id,
		new_reason: input.reason,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
