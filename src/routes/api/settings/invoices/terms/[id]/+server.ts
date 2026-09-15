import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { invoiceTermWriteError } from '$lib/server/settings/errors';
import {
	invoicePaymentTermRemoveSchema,
	invoicePaymentTermSaveSchema
} from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.invoices.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-invoices-update:${organizationId}`,
			...SAVE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = invoicePaymentTermSaveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('save_invoice_payment_term', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		target_term_id: event.params.id,
		new_name: parsed.data.name,
		new_rule: parsed.data.rule,
		new_net_days: parsed.data.net_days
	});

	if (error) return invoiceTermWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// Removal archives the term rather than deleting it -- an invoice issued under it keeps pointing at it.
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.invoices.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-invoices-delete:${organizationId}`,
			...SAVE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = invoicePaymentTermRemoveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('remove_invoice_payment_term', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		target_term_id: event.params.id
	});

	if (error) return invoiceTermWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
