import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { destinationActorName } from '$lib/server/communications/sms-destination-ops';
import { OPT_OUT_LANGUAGES } from '$lib/communications/sms-opt-out-words';

const bodySchema = z.object({
	organization_id: z.string().uuid(),
	language: z.string().refine((value) => value in OPT_OUT_LANGUAGES, 'Unknown language.')
});

// Stage 10 Part 5d: "Mark as done" on an opt-out words task. The person added the language's words in the
// business's Twilio Advanced Opt-Out and says so; Twilio offers no API for it. A second press, or a
// teammate's, finds it already added and says who.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsed = bodySchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) return json({ error: 'The task is invalid.' }, { status: 422 });
	const { organization_id: organizationId, language } = parsed.data;

	try {
		const client = getOwnerSupabaseClient();
		const actorName = destinationActorName(session);
		const result = await client.rpc('communication_sms_add_opt_out_language', {
			p_organization_id: organizationId,
			p_language: language,
			p_actor_name: actorName
		});
		if (result.error) throw result.error;

		if (!result.data?.language) {
			const { data, error } = await client
				.from('communication_sms_opt_out_languages')
				.select('added_at, added_by_name')
				.eq('organization_id', organizationId)
				.eq('language', language)
				.maybeSingle();
			if (error) throw error;
			return json(
				{
					error: 'Someone already finished this task.',
					already_finished: {
						kind: 'opt_out_added',
						at: data?.added_at ?? new Date().toISOString(),
						who: data?.added_by_name ?? null
					}
				},
				{ status: 409 }
			);
		}

		await recordOwnerAccessAudit(client, {
			organization_id: organizationId,
			email: session.email,
			event_type: 'communication_sms_opt_out_language_added',
			target_type: 'communication_sms_opt_out_language',
			target_key: language,
			before_state: {},
			after_state: { language }
		});

		return json(
			{ language: result.data, actor_name: actorName },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not record the opt-out words.', error);
		return json({ error: 'The opt-out words could not be marked as done.' }, { status: 500 });
	}
};
