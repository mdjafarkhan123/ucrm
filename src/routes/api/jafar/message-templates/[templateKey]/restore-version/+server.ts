import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TEMPLATE_ROW_SELECT } from '$lib/server/jafar/message-templates';
import { restoreVersionSchema, templateKeySchema } from '$lib/server/validation/message-template.schema';

/**
 * Resets the draft only -- publishing is a separate explicit step. Omitting `version`
 * (or passing 1) restores the original default wording, since version 1 of every template
 * was seeded as exactly that default; the UI's "Reset to default" button and its "restore
 * this version" action on an older entry both call this same endpoint.
 */
export const POST: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();

	const parsedKey = templateKeySchema.safeParse(event.params.templateKey);
	if (!parsedKey.success) return json({ error: 'Unknown message template.' }, { status: 404 });

	let rawBody: unknown;
	try {
		const text = await event.request.text();
		rawBody = text ? JSON.parse(text) : {};
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = restoreVersionSchema.safeParse(rawBody);
	if (!parsed.success) return json({ error: 'The version to restore is invalid.' }, { status: 422 });
	const targetVersion = parsed.data.version ?? 1;

	try {
		const client = getOwnerSupabaseClient();
		const { data: original, error: originalError } = await client
			.from('platform_message_template_versions')
			.select('subject, body')
			.eq('template_key', parsedKey.data)
			.eq('version', targetVersion)
			.maybeSingle();
		if (originalError) throw originalError;
		if (!original) return json({ error: 'That version was not found.' }, { status: 404 });

		const { data, error } = await client
			.from('platform_message_templates')
			.update({ subject_draft: original.subject, body_draft: original.body })
			.eq('template_key', parsedKey.data)
			.select(TEMPLATE_ROW_SELECT)
			.maybeSingle();
		if (error) throw error;
		if (!data) return json({ error: 'Unknown message template.' }, { status: 404 });

		return json({ template: data });
	} catch (error) {
		console.error('Could not restore the template draft.', error);
		return json({ error: 'The draft could not be restored.' }, { status: 500 });
	}
};
