import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { invoiceOnlinePartialPaymentsSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// "Allow partial online payments" for one invoice. Not part of the document, so it can change after the invoice
// is sent. The command checks invoices.edit and refuses progress invoices.
export const PATCH: RequestHandler = async (event) => {
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

	const parsed = invoiceOnlinePartialPaymentsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_invoice_online_partial_payments', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		new_allowed: parsed.data.allowed
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
