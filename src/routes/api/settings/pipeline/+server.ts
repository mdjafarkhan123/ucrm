import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { isStale, settingsWriteError, staleSettingsResponse } from '$lib/server/settings/errors';
import { pipelineSettingsSchema } from '$lib/server/validation/settings.schema';
import { enabledCustomStages } from '$lib/server/pipeline/stages';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Settings → Pipeline. Its own read and its own revision, kept apart from the three Business Profile
// sections: turning the detailed board on must never collide with somebody editing the company address.
// The Assessment toggle and the custom stages share that one revision and are saved together.
//
// The board itself does not read this route. It gets the preference from the Pipeline summary query,
// which it already holds and already refreshes; this route exists for the Settings form, which needs the
// current value and the revision to save against.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const [{ data, error }, stagesLookup] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select(
				'pipeline_detailed_assessment_stages, pipeline_inactivity_days, pipeline_revision, pipeline_updated_by, pipeline_updated_at'
			)
			.eq('organization_id', check.auth.organization.id)
			.maybeSingle(),
		enabledCustomStages(event.locals.supabase, check.auth.organization.id)
	]);

	if (error || !stagesLookup.ok) return databaseError();
	if (!data) return notFound('These business settings could not be found.');

	// Who saved last, by name. One extra read only once somebody has actually saved.
	let editorName: string | null = null;
	if (data.pipeline_updated_by) {
		const { data: editor } = await event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', data.pipeline_updated_by)
			.maybeSingle();
		editorName = editor?.full_name ?? null;
	}

	return json(
		{
			permissions: { view: true, edit: hasPermission(check.access, 'settings.business.edit') },
			pipeline: {
				detailed_assessment_stages: data.pipeline_detailed_assessment_stages,
				// Each built-in stage's warning days. The database keeps exactly the seven stages in it.
				inactivity_days: data.pipeline_inactivity_days,
				// Every enabled custom stage, in board order. The form saves the whole list back.
				stages: stagesLookup.stages,
				revision: data.pipeline_revision,
				last_editor: data.pipeline_updated_by
					? { name: editorName, at: data.pipeline_updated_at }
					: null
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Explicit Save, the same shape branding uses: permission, rate limit, JSON guard, Zod, then the command
// that owns the revision check and the audit row.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-pipeline-save:${organizationId}`,
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

	const parsed = pipelineSettingsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('save_pipeline_settings', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		new_detailed_assessment_stages: parsed.data.detailed_assessment_stages,
		new_stages: parsed.data.stages,
		new_inactivity_days: parsed.data.inactivity_days
	});

	if (error) return settingsWriteError(error);
	if (isStale(data)) return staleSettingsResponse(data);

	return json(data, { headers: NO_STORE_HEADERS });
};
