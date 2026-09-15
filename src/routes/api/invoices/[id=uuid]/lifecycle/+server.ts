import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { invoiceLifecycleSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// The four supported close/correction transitions for an issued bill, each mapping to a database command.
// One route with an `action` discriminator, because from the office's point of view
// this is one operation. Every command re-checks its own permission (invoices.void / invoices.bad_debt /
// invoices.record_payment), re-locks the row and re-runs its guards — including D2, where void refuses while
// ordinary payments are still applied and the message comes straight back to the dialog. None takes a
// revision; the idempotency key makes a double-press replay instead of double-applying. This route only
// proves membership and validates the shape.
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

	const parsed = invoiceLifecycleSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const input = parsed.data;

	const supabase = event.locals.supabase;
	const target = {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id
	};
	const retry = {
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	};

	const command = (() => {
		switch (input.action) {
			case 'void':
				return supabase.rpc('void_invoice', {
					...target,
					new_reason: input.reason,
					new_note: input.note,
					...retry
				});
			case 'write_off':
				return supabase.rpc('write_off_invoice', { ...target, new_note: input.note, ...retry });
			case 'restore_write_off':
				return supabase.rpc('restore_invoice_from_write_off', {
					...target,
					new_reason: input.reason,
					...retry
				});
			case 'reopen':
				return supabase.rpc('reopen_invoice', { ...target, new_reason: input.reason, ...retry });
		}
	})();

	const { data, error } = await command;
	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
