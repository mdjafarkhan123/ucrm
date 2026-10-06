import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { tellOwnerToRestrictRecording } from '$lib/server/setup/training';
import { setupTrainingConsentSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E6 (plan §6): an owner or administrator gives or withdraws recording consent, at any time
// from Ready onward — booked, skipped or delivered. A withdrawal hides the recording link at once and gives Jafar
// a task to restrict the video where it is hosted.

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
	const parsed = setupTrainingConsentSchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'Choose yes or no.' });

	const { data, error } = await event.locals.supabase.rpc('client_set_setup_training_consent', {
		target_organization_id: organizationId,
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
