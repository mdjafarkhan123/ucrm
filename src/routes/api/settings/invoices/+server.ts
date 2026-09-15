import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { invoiceTermWriteError } from '$lib/server/settings/errors';
import { invoicePaymentTermSaveSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Invoice settings is hidden entirely from every role except owner and admin, so the one permission that
// gates Settings → Invoices also gates this read — same convention as Settings → Taxes.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.invoices.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	const [termsResult, settingsResult] = await Promise.all([
		event.locals.supabase
			.from('invoice_payment_terms')
			.select('id, name, rule, net_days, is_protected')
			.eq('organization_id', organizationId)
			.is('archived_at', null)
			.order('position', { ascending: true })
			.order('name', { ascending: true }),
		event.locals.supabase
			.from('organization_settings')
			.select(
				'invoice_default_term_residential_id, invoice_default_term_commercial_id, invoice_settings_revision, invoice_settings_updated_by, invoice_settings_updated_at'
			)
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);

	if (termsResult.error || settingsResult.error) return databaseError();

	const settings = settingsResult.data;
	let editorName: string | null = null;
	if (settings?.invoice_settings_updated_by) {
		const { data: editor } = await event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', settings.invoice_settings_updated_by)
			.maybeSingle();
		editorName = editor?.full_name ?? null;
	}

	return json(
		{
			terms: termsResult.data ?? [],
			defaults: {
				residential_term_id: settings?.invoice_default_term_residential_id ?? null,
				commercial_term_id: settings?.invoice_default_term_commercial_id ?? null,
				revision: settings?.invoice_settings_revision ?? 0,
				last_editor: settings?.invoice_settings_updated_by
					? { name: editorName, at: settings.invoice_settings_updated_at }
					: null
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.invoices.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-invoices-create:${organizationId}`,
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
		target_term_id: null,
		new_name: parsed.data.name,
		new_rule: parsed.data.rule,
		new_net_days: parsed.data.net_days
	});

	if (error) return invoiceTermWriteError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
