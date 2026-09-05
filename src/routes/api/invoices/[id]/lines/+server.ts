import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { replaceInvoiceLinesSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Replacing a draft's lines in one all-or-nothing save. The command checks invoices.edit and view_price
// itself and refuses a stale revision, so the route only proves membership and validates the shape. No money
// comes back: the page reloads the invoice, so the amounts stay behind the database's own price gate.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = replaceInvoiceLinesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('replace_invoice_lines', {
		target_organization_id: auth.organization.id,
		target_invoice_id: event.params.id,
		expected_revision: input.expected_revision,
		new_lines: input.lines
	});

	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
