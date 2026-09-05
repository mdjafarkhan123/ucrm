import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { updateInvoiceContractDisclaimerSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// The draft's contract disclaimer. The command checks invoices.edit, refuses a stale revision and refuses
// once the document has frozen, so the route only proves membership and validates the shape.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateInvoiceContractDisclaimerSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('update_invoice_contract_disclaimer', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		expected_revision: input.expected_revision,
		new_disclaimer: input.contract_disclaimer
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
