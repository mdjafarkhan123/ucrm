import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { TEMPLATE_PLACEHOLDERS, type TemplateKey } from '$lib/server/jafar/message-templates';

export const GET: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client
			.from('platform_message_templates')
			.select(
				'template_key, published_version, published_at, published_by_owner_email, updated_at'
			)
			.order('template_key');
		if (error) throw error;

		return json({
			templates: (data ?? []).map((row) => ({
				...row,
				placeholders: TEMPLATE_PLACEHOLDERS[row.template_key as TemplateKey]
			}))
		});
	} catch (error) {
		console.error('Could not load message templates.', error);
		return json({ error: 'Message templates could not be loaded.' }, { status: 500 });
	}
};
