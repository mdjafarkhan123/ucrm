import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { sendTrainingBookedEmails } from '$lib/server/setup/training';
import type { TrainingAttendee } from '$lib/setup/training';
import { setupTrainingBookingSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E6 (plan §6): Jafar books training, or moves it, with the confirmed time and the Meet or Zoom
// link — before or after delivery. A booking replaces an owner's skip. The attendees the client named are emailed
// the details; the booking stands even if the email cannot be queued, and the reply says so.

type BookResult = {
	status: 'booked' | 'changed' | 'unchanged';
	booked_at?: string;
	meeting_at?: string;
	meeting_url?: string;
	time_zone?: string | null;
	attendees?: TrainingAttendee[];
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
	const parsed = setupTrainingBookingSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Check the booking.' });

	const client = getOwnerSupabaseClient();
	const { data, error } = await client.rpc('owner_book_setup_training', {
		target_organization_id: organizationId.data,
		new_meeting_at: parsed.data.meeting_at,
		new_meeting_url: parsed.data.meeting_url,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not book the training.', error);
		return databaseError();
	}
	const result = data as unknown as BookResult;

	let emailed = true;
	if (
		result.status !== 'unchanged' &&
		result.booked_at &&
		result.meeting_at &&
		result.meeting_url
	) {
		try {
			await sendTrainingBookedEmails(client, {
				organizationId: organizationId.data,
				bookedAt: result.booked_at,
				meetingAt: result.meeting_at,
				meetingUrl: result.meeting_url,
				timeZone: result.time_zone ?? null,
				attendees: result.attendees ?? [],
				changed: result.status === 'changed'
			});
		} catch (error) {
			console.error('Could not queue the training emails.', error);
			emailed = false;
		}
	}
	return json(
		{ status: result.status, emailed, attendees: result.attendees?.length ?? 0 },
		{ headers: NO_STORE_HEADERS }
	);
};
