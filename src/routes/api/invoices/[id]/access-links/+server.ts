import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { issueInvoiceAccessLinkSchema } from '$lib/server/validation/invoices.schema';
import { updateInvoiceError } from '$lib/server/invoices/errors';
import { createInvoiceAccessToken, invoiceAccessLinkUrl } from '$lib/server/invoices/access-links';

// Making the customer's door by hand — the "Copy customer link" press. The token is generated here, in Node,
// and the database is handed only its SHA-256, so the raw link exists exactly once, in this response, on its
// way to the person who asked for it. It is never stored, never logged, and cannot be read back afterwards.
//
// Asking twice does not leave two working doors: the write function rotates the invoice's older links in the
// same transaction. Only offered for an issued, not-voided, not-replaced invoice — the resolver would refuse
// a link to anything else anyway.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.send');
	if ('response' in check) return check.response;

	let body: unknown = {};
	const raw = await event.request.text();
	if (raw.trim().length > 0) {
		try {
			body = JSON.parse(raw);
		} catch {
			return validationError({ form: 'Request body must be valid JSON.' });
		}
	}

	const parsed = issueInvoiceAccessLinkSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { token, tokenHash } = createInvoiceAccessToken();

	const { data, error } = await event.locals.supabase.rpc('issue_invoice_access_link', {
		target_invoice_id: event.params.id,
		supplied_token_hash: tokenHash
	});

	if (error) return updateInvoiceError(error);
	return json(
		{ ...(data as Record<string, unknown>), url: invoiceAccessLinkUrl(event.url.origin, token) },
		{ headers: NO_STORE_HEADERS }
	);
};
