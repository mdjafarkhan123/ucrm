import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { paymentAllocationActionSchema } from '$lib/server/validation/invoices.schema';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Paid-launch-trust Part 11: the two ways an already-applied payment gets corrected. `id` is the allocation
// id -- not addressable anywhere else in the product -- and the action says whether it comes back off
// (unapply_client_payment) or moves to another of the same client's invoices (move_client_payment), both
// built and pgTAP-tested in 3b-1. Gated on invoices.correct_payment here as well as inside each command: a
// permission that lets someone record a payment does not thereby let them move one that is already on a
// bill. Neither command takes a revision; the idempotency key makes a double press replay instead of
// double-correcting.
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

	const parsed = paymentAllocationActionSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const supabase = event.locals.supabase;
	const target = {
		target_organization_id: check.auth.organization.id,
		target_allocation_id: event.params.id
	};
	const retry = {
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	};

	const command =
		input.action === 'unapply'
			? supabase.rpc('unapply_client_payment', { ...target, new_reason: input.reason, ...retry })
			: supabase.rpc('move_client_payment', {
					...target,
					target_invoice_id: input.target_invoice_id,
					new_amount_minor: input.amount_minor,
					new_reason: input.reason,
					...retry
				});

	const { data, error } = await command;
	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
