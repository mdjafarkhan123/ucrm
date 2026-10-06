import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import {
	requireSetupEditor,
	requireSetupReader,
	setupWriteError,
	setupWriteLimited
} from '$lib/server/setup/access';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { readSetupTraining, tellOwnerToRestrictRecording } from '$lib/server/setup/training';
import { setupTrainingSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E6 (plan §6): the training record (GET) and an owner's or administrator's training details
// (POST), from Ready for Uplift until Uplift books. Read and written with the client's own session, so row
// security and the setup editor check apply. `is_owner` says whether this person may say they don't need training.

export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	try {
		const training = await readSetupTraining(event.locals.supabase, check.auth.organization.id);
		return json(
			{ training, is_owner: check.auth.organization.role === 'owner' },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read the training details.', error);
		return databaseError();
	}
};

export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;

	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupTrainingSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Check the details.' });

	const { data, error } = await event.locals.supabase.rpc('client_save_setup_training', {
		target_organization_id: organizationId,
		new_attendees: parsed.data.attendees,
		new_time_zone: parsed.data.time_zone,
		new_preferred_times: parsed.data.preferred_times,
		new_needs: parsed.data.needs ?? undefined,
		new_top_tasks: parsed.data.top_tasks ?? undefined,
		consent: parsed.data.recording_consent
	});
	if (error) return setupWriteError(error);
	const result = data as unknown as { status: string; restrict_recording: boolean };
	if (result.restrict_recording)
		await tellOwnerToRestrictRecording(getOwnerSupabaseClient(), {
			organizationId,
			origin: env.APP_URL?.trim() || event.url.origin
		});
	return json(result, { headers: NO_STORE_HEADERS });
};
