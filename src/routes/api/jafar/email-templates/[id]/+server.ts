import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { emailTemplateUpdateSchema } from '$lib/server/validation/email-template.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

const TEMPLATE_SELECT = 'id, name, folder, subject, body, version, created_at, updated_at';

export const PATCH: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const { id } = event.params;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = emailTemplateUpdateSchema.safeParse(body);
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

		let template = null;
		if (Object.keys(fields).length > 0) {
			const update: Partial<{
				name: string;
				folder: string | null;
				subject: string;
				body: string;
			}> = {
				...fields
			};
			if ('folder' in fields) update.folder = fields.folder || null;
			const { data, error } = await client
				.from('platform_email_templates')
				.update(update)
				.eq('id', id)
				.select(TEMPLATE_SELECT)
				.maybeSingle();
			if (error) throw error;
			template = data;
		} else {
			const { data, error } = await client
				.from('platform_email_templates')
				.select(TEMPLATE_SELECT)
				.eq('id', id)
				.maybeSingle();
			if (error) throw error;
			template = data;
		}
		if (!template) return json({ error: 'Unknown email template.' }, { status: 404 });

		if (package_keys !== undefined) {
			const { error: clearError } = await client
				.from('platform_email_template_packages')
				.delete()
				.eq('template_id', id);
			if (clearError) throw clearError;

			if (package_keys.length) {
				const { error: visibilityError } = await client
					.from('platform_email_template_packages')
					.insert(package_keys.map((package_key) => ({ template_id: id, package_key })));
				if (visibilityError) throw visibilityError;
			}
		}

		const { data: visibility, error: visibilityReadError } = await client
			.from('platform_email_template_packages')
			.select('package_key')
			.eq('template_id', id);
		if (visibilityReadError) throw visibilityReadError;

		return json({
			template: { ...template, package_keys: (visibility ?? []).map((row) => row.package_key) }
		});
	} catch (error) {
		console.error('Could not save the email template.', error);
		return json({ error: 'The email template could not be saved.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const { id } = event.params;

	try {
		const client = getOwnerSupabaseClient();
		const { error, count } = await client
			.from('platform_email_templates')
			.delete({ count: 'exact' })
			.eq('id', id);
		if (error) throw error;
		if (!count) return json({ error: 'Unknown email template.' }, { status: 404 });

		return json({ ok: true });
	} catch (error) {
		console.error('Could not delete the email template.', error);
		return json({ error: 'The email template could not be deleted.' }, { status: 500 });
	}
};
