import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized, validationError } from '$lib/server/api/errors';
import { enforceOrganizationWriteRateLimit } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { invoiceReplacementSchema } from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { updateInvoiceError } from '$lib/server/invoices/errors';

// Correcting an issued bill, or rebilling a voided one (D3, D4, D6). `correct` and `rebill` make the
// replacement draft from the invoice in the URL; `activate` issues that draft (the invoice in the URL is the
// draft) and retires the original, moving what was already paid across. Each command re-checks its own
// permission, locks, and guards, so this route proves membership and validates the shape.
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

	const parsed = invoiceReplacementSchema.safeParse(body);
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
			case 'correct':
				return supabase.rpc('prepare_invoice_correction', {
					...target,
					expected_revision: input.expected_revision,
					...retry
				});
			case 'rebill':
				return supabase.rpc('rebill_voided_invoice', { ...target, ...retry });
			case 'activate':
				return supabase.rpc('activate_invoice_replacement', {
					...target,
					expected_revision: input.expected_revision,
					previewed_difference_minor: input.previewed_difference_minor,
					new_issue_method: input.method,
					...retry
				});
		}
	})();

	const { data, error } = await command;
	if (error?.code === '23505') {
		// A correction or rebill already started: hand back its draft so the page can open it instead.
		const { data: existing } = await supabase
			.from('invoices')
			.select('id')
			.eq('organization_id', auth.organization.id)
			.eq('predecessor_invoice_id', event.params.id)
			.maybeSingle();
		return json(
			{ error: error.message, reason: 'already_started', invoice_id: existing?.id ?? null },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	}
	if (error) return updateInvoiceError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
