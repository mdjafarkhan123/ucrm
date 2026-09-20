import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	copyPlatformTemplate,
	listOrganizationTemplates,
	listPlatformTemplates,
	TemplateNotFoundError
} from '$lib/server/marketing/templates';

// Jafar's starter library plus the organization's own copies. Listing needs marketing.view; copying a
// starter into the organization's library needs marketing.draft.

const copySchema = z.object({
	platform_template_key: z.string().trim().min(1).max(60)
});

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	try {
		const [platformTemplates, templates] = await Promise.all([
			listPlatformTemplates(),
			listOrganizationTemplates(access.auth.organization.id)
		]);
		return json(
			{ platform_templates: platformTemplates, templates },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not list marketing templates.', error);
		return databaseError();
	}
};

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.draft');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = copySchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const template = await copyPlatformTemplate(
			access.auth.organization.id,
			access.auth.user.id,
			parsed.data.platform_template_key
		);
		return json({ template }, { status: 201, headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof TemplateNotFoundError) {
			return notFound('That starter template no longer exists.');
		}
		console.error('Could not copy a marketing template.', error);
		return databaseError();
	}
};
