import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { missingRequiredPlaceholders } from '$lib/server/jafar/message-templates';
import { templateKeySchema } from '$lib/server/validation/message-template.schema';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedKey = templateKeySchema.safeParse(event.params.templateKey);
	if (!parsedKey.success) return json({ error: 'Unknown message template.' }, { status: 404 });

	const client = getOwnerSupabaseClient();

	try {
		const { data: current, error: readError } = await client
			.from('platform_message_templates')
			.select('subject_draft, body_draft')
			.eq('template_key', parsedKey.data)
			.maybeSingle();
		if (readError) throw readError;
		if (!current) return json({ error: 'Unknown message template.' }, { status: 404 });

		if (!current.body_draft || current.body_draft.trim().length === 0) {
			return json({ error: 'Add message content before publishing.' }, { status: 422 });
		}

		const missing = missingRequiredPlaceholders(
			parsedKey.data,
			current.subject_draft,
			current.body_draft
		);
		if (missing.length > 0) {
			return json(
				{ error: 'Required tags are missing from the draft.', missing_placeholders: missing },
				{ status: 422 }
			);
		}

		const { data, error } = await client.rpc('publish_message_template', {
			target_template_key: parsedKey.data,
			actor_email: session.email
		});
		if (error) throw error;

		return json({ template: data });
	} catch (error) {
		console.error('Could not publish the message template.', error);
		return json({ error: 'The message template could not be published.' }, { status: 500 });
	}
};
