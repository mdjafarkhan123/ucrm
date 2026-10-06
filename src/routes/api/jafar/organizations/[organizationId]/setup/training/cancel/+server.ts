import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { sendTrainingCancelledEmails } from '$lib/server/setup/training';
import type { TrainingAttendee } from '$lib/setup/training';

// Client onboarding E6 (plan §6): Jafar cancels the booked training; the attendees are told. Before delivery,
// another booking or an owner skip is then needed before the project can be delivered.

type CancelResult = {
	status: 'cancelled' | 'unchanged';
	event_id?: number;
	meeting_at?: string;
	time_zone?: string | null;
	attendees?: TrainingAttendee[];
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('owner_cancel_setup_training', {
		target_organization_id: organizationId.data,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not cancel the training.', error);
		return databaseError();
	}
	const result = data as unknown as CancelResult;

	let emailed = true;
	if (result.status === 'cancelled' && result.event_id && result.meeting_at) {
		try {
			await sendTrainingCancelledEmails(client, {
				organizationId: organizationId.data,
				eventId: result.event_id,
				meetingAt: result.meeting_at,
				timeZone: result.time_zone ?? null,
				attendees: result.attendees ?? []
			});
		} catch (error) {
			console.error('Could not queue the cancellation emails.', error);
			emailed = false;
		}
	}
	return json({ status: result.status, emailed }, { headers: NO_STORE_HEADERS });
};
