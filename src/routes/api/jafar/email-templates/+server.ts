import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { emailTemplateCreateSchema } from '$lib/server/validation/email-template.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

const TEMPLATE_SELECT = 'id, name, folder, subject, body, version, created_at, updated_at';

// The whole library at once, same as /api/jafar/packages and /api/jafar/message-templates -- Jafar's
// owner-managed content lists are a bounded handful of rows, not a paginated corpus.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const [templatesResult, visibilityResult, packagesResult] = await Promise.all([
			client.from('platform_email_templates').select(TEMPLATE_SELECT).order('name'),
			client.from('platform_email_template_packages').select('template_id, package_key'),
			client.from('platform_packages').select('package_key, display_name').order('sort_order')
		]);
		if (templatesResult.error) throw templatesResult.error;
		if (visibilityResult.error) throw visibilityResult.error;
		if (packagesResult.error) throw packagesResult.error;

		const visibilityByTemplate = new Map<string, string[]>();
		for (const row of visibilityResult.data ?? []) {
			const keys = visibilityByTemplate.get(row.template_id) ?? [];
			keys.push(row.package_key);
			visibilityByTemplate.set(row.template_id, keys);
		}

		return json({
			templates: (templatesResult.data ?? []).map((template) => ({
				...template,
				package_keys: visibilityByTemplate.get(template.id) ?? []
			})),
			packages: packagesResult.data ?? []
		});
	} catch (error) {
		console.error('Could not load email templates.', error);
		return json({ error: 'Email templates could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = emailTemplateCreateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { package_keys, ...fields } = parsed.data;
		const { data: template, error } = await client
			.from('platform_email_templates')
			.insert({ ...fields, folder: fields.folder || null })
			.select(TEMPLATE_SELECT)
			.single();
		if (error) throw error;

		if (package_keys?.length) {
			const { error: visibilityError } = await client
				.from('platform_email_template_packages')
				.insert(package_keys.map((package_key) => ({ template_id: template.id, package_key })));
			if (visibilityError) throw visibilityError;
		}

		return json({ template: { ...template, package_keys: package_keys ?? [] } }, { status: 201 });
	} catch (error) {
		console.error('Could not create the email template.', error);
		return json({ error: 'The email template could not be created.' }, { status: 500 });
	}
};
