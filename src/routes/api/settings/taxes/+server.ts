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
import { taxRateWriteError } from '$lib/server/settings/errors';
import { taxRateCreateSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Taxes is hidden entirely from every role except owner and admin, so the one permission that gates
// Settings → Taxes also gates this read — there is no broader "view" key the way Business Profile has one.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	const [ratesResult, settingsResult] = await Promise.all([
		event.locals.supabase
			.from('organization_tax_rates')
			.select('id, name, rate_basis_points, is_active, revision')
			.eq('organization_id', organizationId)
			.order('name'),
		event.locals.supabase
			.from('organization_settings')
			.select(
				'tax_default_source, tax_default_rate_id, tax_revision, tax_updated_by, tax_updated_at'
			)
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);

	if (ratesResult.error || settingsResult.error) return databaseError();

	const settings = settingsResult.data;
	let editorName: string | null = null;
	if (settings?.tax_updated_by) {
		const { data: editor } = await event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', settings.tax_updated_by)
			.maybeSingle();
		editorName = editor?.full_name ?? null;
	}

	return json(
		{
			rates: ratesResult.data ?? [],
			default: {
				source: settings?.tax_default_source ?? 'not_configured',
				rate_id: settings?.tax_default_rate_id ?? null,
				revision: settings?.tax_revision ?? 1,
				last_editor: settings?.tax_updated_by
					? { name: editorName, at: settings.tax_updated_at }
					: null
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.taxes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-taxes-create:${organizationId}`,
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

	const parsed = taxRateCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('create_organization_tax_rate', {
		target_organization_id: organizationId,
		new_name: parsed.data.name,
		new_rate_basis_points: parsed.data.rate_basis_points
	});

	if (error) return taxRateWriteError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
