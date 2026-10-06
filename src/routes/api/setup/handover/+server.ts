import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSetupReader } from '$lib/server/setup/access';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readLaunchApprovals } from '$lib/server/setup/launch-approval';
import { readClientProviderWaits } from '$lib/server/setup/provider-waits';
import {
	readHandoverEvents,
	readSetupHandover,
	readSetupTraining,
	readTrainingRecording
} from '$lib/server/setup/training';

// Client onboarding E6 (plan §6): the handover pack for the client's owners and administrators — Uplift's access
// and ownership summary, guides, launch approvals, outside waits still open, training, and the recording while the
// client consents. It opens once the project is delivered. The recording link is read with the service role only
// after consent is confirmed, so it is never readable through the client's own session.

export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	try {
		const handover = await readSetupHandover(supabase, organizationId);
		if (!handover?.delivered_at)
			return json({ delivered: false }, { headers: PRIVATE_READ_HEADERS });

		const [training, approvals, waits, events, recording] = await Promise.all([
			readSetupTraining(supabase, organizationId),
			readLaunchApprovals(supabase, organizationId),
			readClientProviderWaits(supabase, organizationId),
			readHandoverEvents(supabase, organizationId),
			readTrainingRecording(getOwnerSupabaseClient(), organizationId)
		]);
		if (!waits) return databaseError();

		return json(
			{
				delivered: true,
				handover,
				training,
				approvals: approvals.filter((request) => request.status === 'approved'),
				open_waits: waits.filter(
					(wait) => wait.status !== 'approved' && wait.status !== 'unavailable'
				),
				events,
				recording_url:
					recording?.recording_consent === true ? (recording.recording_url ?? null) : null
			},
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read the handover pack.', error);
		return databaseError();
	}
};
