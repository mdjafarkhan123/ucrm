import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { recordInvoicePaymentSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Collect Payment, single invoice. No new database command: 3b-1's record_client_payment already records the
// receipt and applies it in one transaction when it is handed a one-entry allocation list. The command itself
// re-checks the invoice belongs to the given client and caps the amount against what it still owes, so this
// route repeats none of that. Spreading one payment across a client's several open invoices is a later,
// deferred screen.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

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
		new_allocations: [{ invoice_id: event.params.id, amount_minor: input.amount_minor }],
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
