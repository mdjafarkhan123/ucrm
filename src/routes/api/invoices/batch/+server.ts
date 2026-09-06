import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { batchInvoiceSchema } from '$lib/server/validation/invoices.schema';
import { createInvoiceError } from '$lib/server/invoices/errors';

// Billing a page of the ready-to-bill queue in one go (Part 8a).
//
// Everything real happens inside `create_invoices_in_batch`: one transaction that completes the ticked
// visits, writes one draft per client per tax rate, claims each draft's work and clears the reminders that
// asked for it. All-or-nothing, so this route has nothing to undo when something refuses.
//
// It checks `invoices.create`, `invoices.view_price` and — only when unfinished visits were ticked —
// `jobs.complete`, each for itself, so the route only proves membership. A doubled click sends the same
// idempotency key and gets the first batch's summary back with `applied: false`.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = batchInvoiceSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('create_invoices_in_batch', {
		target_organization_id: auth.organization.id,
		new_job_ids: input.job_ids,
		new_complete_visit_ids: input.complete_visit_ids,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	});

	// The batch refuses in the same named shapes a single invoice does — a permission it does not have, work
	// that is already billed, a client whose selection is too large — and each raise already carries the
	// sentence a person should read.
	if (error) return createInvoiceError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
