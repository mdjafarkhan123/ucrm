import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setInvoiceTaxSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// How a draft is taxed, resolved one of the five shared ways. The command derives the property from the
// invoice's own first service property and freezes the real name and rate at save time; it checks
// invoices.edit and view_price itself and refuses a stale revision. `save_as_reusable` is accepted from the
// shared Tax card but ignored here — unlike the job command, `set_invoice_tax` does not persist a one-off
// rate to the organization's shared list.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = setInvoiceTaxSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('set_invoice_tax', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		expected_revision: input.expected_revision,
		new_source: input.source,
		new_rate_id: input.rate_id,
		new_custom_name: input.custom_name,
		new_custom_rate_basis_points: input.custom_rate_basis_points ?? null
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
