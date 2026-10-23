import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runTwilioReviewChecks } from '$lib/server/communications/twilio-review-checks';

const checkSchema = z.object({}).strict();

// Stage 10 Part 5b-2: Check now on the Waiting on Twilio tab. Asks Twilio straight away what the daily safety net
// would ask tonight; each answer updates its own record, so pressing it twice only asks twice.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const body = await event.request.json().catch(() => ({}));
	if (!checkSchema.safeParse(body).success) {
		return json({ error: 'Check now takes no details.' }, { status: 422 });
	}

	try {
		const result = await runTwilioReviewChecks(getOwnerSupabaseClient());
		return json(
			{ checked_at: new Date().toISOString(), result },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Check now could not ask Twilio.', error);
		return json({ error: 'Twilio could not be asked just now. Try again.' }, { status: 502 });
	}
};
