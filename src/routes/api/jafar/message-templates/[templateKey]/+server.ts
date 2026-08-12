import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TEMPLATE_PLACEHOLDERS, TEMPLATE_ROW_SELECT } from '$lib/server/jafar/message-templates';
import { templateDraftSchema, templateKeySchema } from '$lib/server/validation/message-template.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();

	const parsedKey = templateKeySchema.safeParse(event.params.templateKey);
	if (!parsedKey.success) return json({ error: 'Unknown message template.' }, { status: 404 });

	try {
		const client = getOwnerSupabaseClient();
		const [templateResult, versionsResult] = await Promise.all([
			client
				.from('platform_message_templates')
				.select(TEMPLATE_ROW_SELECT)
				.eq('template_key', parsedKey.data)
				.maybeSingle(),
			client
				.from('platform_message_template_versions')
				.select('version, subject, body, published_at, published_by_owner_email')
				.eq('template_key', parsedKey.data)
				.order('version', { ascending: false })
		]);
		if (templateResult.error) throw templateResult.error;
		if (versionsResult.error) throw versionsResult.error;
		if (!templateResult.data) return json({ error: 'Unknown message template.' }, { status: 404 });

		return json({
			template: templateResult.data,
			versions: versionsResult.data ?? [],
			placeholders: TEMPLATE_PLACEHOLDERS[parsedKey.data]
		});
	} catch (error) {
		console.error('Could not load the message template.', error);
		return json({ error: 'The message template could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();

	const parsedKey = templateKeySchema.safeParse(event.params.templateKey);
	if (!parsedKey.success) return json({ error: 'Unknown message template.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = templateDraftSchema.safeParse(body);
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
		const { data, error } = await client
			.from('platform_message_templates')
			.update({
				subject_draft: parsed.data.subject_draft ?? null,
				body_draft: parsed.data.body_draft
			})
			.eq('template_key', parsedKey.data)
			.select(TEMPLATE_ROW_SELECT)
			.maybeSingle();
		if (error) throw error;
		if (!data) return json({ error: 'Unknown message template.' }, { status: 404 });

		return json({ template: data });
	} catch (error) {
		console.error('Could not save the template draft.', error);
		return json({ error: 'The draft could not be saved.' }, { status: 500 });
	}
};
