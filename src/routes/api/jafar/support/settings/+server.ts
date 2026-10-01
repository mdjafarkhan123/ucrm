import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordPlatformAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSupportSettings } from '$lib/server/support/inbox';
import { supportSettingsSchema } from '$lib/server/validation/support.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// How Uplift appears in the messenger: the responder's name on every reply, and Uplift's own sentence about
// its hours and usual reply time. Contractors read the sentence exactly as written, so it is a promise.
export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = supportSettingsSchema.safeParse(body);
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
		const before = await readSupportSettings(client);
		const { error } = await client
			.from('platform_support_settings')
			.upsert({ id: true, ...parsed.data }, { onConflict: 'id' });
		if (error) throw error;

		await recordPlatformAudit(client, {
			email: session.email,
			event_type: 'support_settings.updated',
			target_type: 'platform_support_settings',
			target_key: 'singleton',
			before_state: before,
			after_state: parsed.data
		});

		return json({ settings: parsed.data });
	} catch (error) {
		console.error('Could not save support settings.', error);
		return json({ error: 'Support settings could not be saved.' }, { status: 500 });
	}
};
