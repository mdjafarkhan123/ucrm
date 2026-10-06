import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	readHandoverEvents,
	readSetupHandover,
	readSetupTraining,
	readTrainingRecording
} from '$lib/server/setup/training';
import { setupHandoverSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E6 (plan §6, §8): Jafar's view of training and handover (GET) — the client's training details,
// his booking, the recording link and whether consent stands, Live, his summary and guides, Delivered and the
// history — and saving his access and ownership summary and guides (POST), whole.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');
	const client = getOwnerSupabaseClient();
	try {
		const [handover, training, recording, events] = await Promise.all([
			readSetupHandover(client, organizationId.data),
			readSetupTraining(client, organizationId.data),
			readTrainingRecording(client, organizationId.data),
			readHandoverEvents(client, organizationId.data)
		]);
		return json(
			{
				handover,
				training,
				recording_url: recording?.recording_url ?? null,
				recording_added_at: recording?.recording_added_at ?? null,
				events
			},
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read the training and handover.', error);
		return databaseError();
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupHandoverSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Check the handover.' });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_save_setup_handover', {
		target_organization_id: organizationId.data,
		// Null clears the summary; the generated type does not know the argument takes null.
		new_access_summary: parsed.data.access_summary as string,
		new_guides: parsed.data.guides,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not save the handover.', error);
		return databaseError();
	}
	return json(data, { headers: NO_STORE_HEADERS });
};
