import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { emailTemplateWriteError } from '$lib/server/communications/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

const TEMPLATE_SELECT =
	'id, folder, name, subject, body, source_template_id, source_version_copied_at, created_at, updated_at';
const WRITE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// The explicit "adopt" action the contract requires: a newer platform version is never pulled in silently,
// only through this dedicated endpoint that re-snapshots the platform template's current subject/body/name.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.send');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `communications-email-templates-adopt:${organizationId}`,
			...WRITE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const { data: existing, error: existingError } = await event.locals.supabase
		.from('communications_email_templates')
		.select('id, source_template_id')
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.maybeSingle();
	if (existingError) return databaseError();
	if (!existing) return notFound('That email template could not be found.');
	if (!existing.source_template_id) {
		return json({ error: 'This template was not copied from the library.' }, { status: 409 });
	}

	const { data: source, error: sourceError } = await getOwnerSupabaseClient()
		.from('platform_email_templates')
		.select('name, subject, body, version')
		.eq('id', existing.source_template_id)
		.maybeSingle();
	if (sourceError) return databaseError();
	if (!source)
		return json({ error: 'That platform template is no longer available.' }, { status: 409 });

	const { data, error } = await event.locals.supabase
		.from('communications_email_templates')
		.update({
			name: source.name,
			subject: source.subject,
			body: source.body,
			source_version_copied_at: source.version
		})
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.select(TEMPLATE_SELECT)
		.maybeSingle();

	if (error) return emailTemplateWriteError(error);
	if (!data) return notFound('That email template could not be found.');
	return json({ item: data }, { headers: NO_STORE_HEADERS });
};
