import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	getOrCreateOwnerSettings,
	readOwnerSettingsAttention
} from '$lib/server/jafar/owner-settings';
import { ownerSettingsPatchSchema } from '$lib/server/validation/owner-settings.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const [settings, attention] = await Promise.all([
			getOrCreateOwnerSettings(client),
			readOwnerSettingsAttention(client)
		]);
		return json({ settings, attention });
	} catch (error) {
		console.error('Could not load owner settings.', error);
		return json({ error: 'Settings could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = ownerSettingsPatchSchema.safeParse(body);
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
		// A field the section did not send goes as null, which the function reads as "keep what is saved".
		// The generated types cannot express a nullable function argument.
		const keep = null as unknown as string;
		const { data, error } = await client.rpc('update_owner_settings', {
			actor_email: session.email,
			new_privacy_policy_url: parsed.data.privacy_policy_url ?? keep,
			new_privacy_policy_version: parsed.data.privacy_policy_version ?? keep,
			new_payment_instructions: parsed.data.payment_instructions ?? keep,
			new_sender_display_name: parsed.data.sender_display_name ?? keep,
			new_reply_to_address: parsed.data.reply_to_address ?? keep,
			new_alert_recipient_emails:
				parsed.data.alert_recipient_emails ?? (keep as unknown as string[])
		});
		if (error) throw error;

		return json({ settings: data });
	} catch (error) {
		console.error('Could not save owner settings.', error);
		return json({ error: 'Settings could not be saved.' }, { status: 500 });
	}
};
