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
import { contactMatchPrioritySchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Settings → Contact matching. HighLevel's Contact deduplication preference: when a website chat or form
// arrives with a phone that belongs to one client and an email that belongs to another, this says which one
// it joins. Its own read and its own revision, the same shape as Settings → Pipeline. The matching itself
// happens in the database (private.match_client_by_contact); this route only reads and saves the choice.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('organization_settings')
		.select(
			'contact_match_priority, contact_match_revision, contact_match_updated_by, contact_match_updated_at'
		)
		.eq('organization_id', check.auth.organization.id)
		.maybeSingle();

	if (error) return databaseError();
	if (!data) return notFound('These business settings could not be found.');

	let editorName: string | null = null;
	if (data.contact_match_updated_by) {
		const { data: editor } = await event.locals.supabase
			.from('profiles')
			.select('full_name')
			.eq('id', data.contact_match_updated_by)
			.maybeSingle();
		editorName = editor?.full_name ?? null;
	}

	return json(
		{
			permissions: { view: true, edit: hasPermission(check.access, 'settings.business.edit') },
			contact_matching: {
				priority: data.contact_match_priority,
				revision: data.contact_match_revision,
				last_editor: data.contact_match_updated_by
					? { name: editorName, at: data.contact_match_updated_at }
					: null
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-contact-matching-save:${organizationId}`,
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

	const parsed = contactMatchPrioritySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('save_contact_match_priority', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		new_priority: parsed.data.priority
	});

	if (error) return settingsWriteError(error);
	if (isStale(data)) return staleSettingsResponse(data);

	return json(data, { headers: NO_STORE_HEADERS });
};
