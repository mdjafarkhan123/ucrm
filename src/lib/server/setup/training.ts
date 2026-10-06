import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { emailBody, greetingName } from '$lib/server/setup/launch-approval';
import {
	HANDOVER_COLUMNS,
	TRAINING_COLUMNS,
	formatMeetingTime,
	type HandoverEvent,
	type SetupHandover,
	type SetupTraining,
	type TrainingAttendee
} from '$lib/setup/training';

// Client onboarding E6: training and handover (plan §6). The reads both sides make and the emails that go out:
// Live and Delivered to the client's owners and administrators, and the booking, a moved booking or a cancellation
// to the attendees the client named. Each email is keyed by the change it reports, so a retry queues nothing twice.
// The recording link is never emailed.

type Client = SupabaseClient<Database>;

/** The training record, without the recording link. With the client's own session, row security applies. */
export async function readSetupTraining(
	supabase: Client,
	organizationId: string
): Promise<SetupTraining | null> {
	const { data, error } = await supabase
		.from('organization_setup_training')
		.select(TRAINING_COLUMNS)
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;
	return data as unknown as SetupTraining | null;
}

export async function readSetupHandover(
	supabase: Client,
	organizationId: string
): Promise<SetupHandover | null> {
	const { data, error } = await supabase
		.from('organization_setup_handover')
		.select(HANDOVER_COLUMNS)
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;
	return data as unknown as SetupHandover | null;
}

/** Newest first. A client has a few dozen at most; the cap keeps it bounded. */
export async function readHandoverEvents(
	supabase: Client,
	organizationId: string
): Promise<HandoverEvent[]> {
	const { data, error } = await supabase
		.from('organization_setup_handover_events')
		.select('id, kind, happened_at, actor_kind, actor_name, detail')
		.eq('organization_id', organizationId)
		.order('happened_at', { ascending: false })
		.limit(200);
	if (error) throw error;
	return data as unknown as HandoverEvent[];
}

/** The recording link and when it was added; service role only. */
export async function readTrainingRecording(service: Client, organizationId: string) {
	const { data, error } = await service
		.from('organization_setup_training')
		.select('recording_url, recording_added_at, recording_consent')
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error) throw error;
	return data;
}

type Recipient = { user_id: string; email: string; name: string | null };

async function readOwnersAndAdmins(client: Client, organizationId: string) {
	const [organization, recipients] = await Promise.all([
		client.from('organizations').select('name').eq('id', organizationId).single(),
		client.rpc('owner_setup_review_recipients', { target_organization_id: organizationId })
	]);
	if (organization.error) throw organization.error;
	if (recipients.error) throw recipients.error;
	return {
		organizationName: organization.data.name,
		recipients: (recipients.data ?? []) as unknown as Recipient[]
	};
}

export function buildLiveEmail(input: {
	recipientName: string | null;
	organizationName: string;
	origin: string;
}) {
	return {
		subject: `${input.organizationName}'s system is live`,
		...emailBody(
			[
				`Hi ${greetingName(input.recipientName)}, ${input.organizationName}'s website and system are now live.`,
				'Next is training. Tell Uplift who is coming and which times suit you — or, if you are the owner and your team doesn’t need it, say so on the Setup page.'
			],
			{ label: 'Arrange training', url: `${input.origin}/setup#training` },
			'Questions? Write to Uplift in Chat with Uplift, in the bottom corner of every screen.'
		)
	};
}

/** To the client's owners and administrators, once each per person. Returns how many were queued. */
export async function sendLiveEmails(
	client: Client,
	input: { organizationId: string; origin: string }
) {
	const { organizationName, recipients } = await readOwnersAndAdmins(client, input.organizationId);
	for (const member of recipients)
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_live',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-live:${input.organizationId}:${member.email.toLowerCase()}`,
			recipientEmail: member.email,
			...buildLiveEmail({ recipientName: member.name, organizationName, origin: input.origin })
		});
	return recipients.length;
}

export function buildDeliveredEmail(input: {
	recipientName: string | null;
	organizationName: string;
	origin: string;
}) {
	return {
		subject: `${input.organizationName}'s project is delivered`,
		...emailBody(
			[
				`Hi ${greetingName(input.recipientName)}, Uplift has delivered ${input.organizationName}'s project.`,
				'Your handover pack has what you need to run it yourself: who owns which account, guides for your team, your launch approval, and anything still waiting on an outside company.'
			],
			{ label: 'Open your handover pack', url: `${input.origin}/setup/handover` },
			'You can open it again any time from Settings. Uplift is still here in Chat with Uplift.'
		)
	};
}

export async function sendDeliveredEmails(
	client: Client,
	input: { organizationId: string; origin: string }
) {
	const { organizationName, recipients } = await readOwnersAndAdmins(client, input.organizationId);
	for (const member of recipients)
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_delivered',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-delivered:${input.organizationId}:${member.email.toLowerCase()}`,
			recipientEmail: member.email,
			...buildDeliveredEmail({ recipientName: member.name, organizationName, origin: input.origin })
		});
	return recipients.length;
}

export function buildTrainingBookedEmail(input: {
	attendeeName: string;
	organizationName: string;
	meetingAt: string;
	meetingUrl: string;
	timeZone: string | null;
	changed: boolean;
}) {
	const when = formatMeetingTime(input.meetingAt, input.timeZone);
	return {
		subject: input.changed
			? `New time for your Uplift training: ${when}`
			: `Your Uplift training is booked: ${when}`,
		...emailBody(
			[
				`Hi ${greetingName(input.attendeeName)}, ${
					input.changed
						? `your Uplift training for ${input.organizationName} has moved to a new time.`
						: `your Uplift training for ${input.organizationName} is booked.`
				}`,
				`When: ${when}`,
				'Join with the button below from a computer if you can, so you can follow along on screen.'
			],
			{ label: 'Join the training', url: input.meetingUrl },
			'Need a different time? Ask your account owner to write to Uplift in Chat with Uplift.'
		)
	};
}

/** To each attendee the client named, once per booking or change. */
export async function sendTrainingBookedEmails(
	client: Client,
	input: {
		organizationId: string;
		bookedAt: string;
		meetingAt: string;
		meetingUrl: string;
		timeZone: string | null;
		attendees: TrainingAttendee[];
		changed: boolean;
	}
) {
	const organization = await client
		.from('organizations')
		.select('name')
		.eq('id', input.organizationId)
		.single();
	if (organization.error) throw organization.error;
	for (const attendee of uniqueAttendees(input.attendees))
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_training_booked',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-training-booked:${input.organizationId}:${input.bookedAt}:${attendee.email.toLowerCase()}`,
			recipientEmail: attendee.email,
			...buildTrainingBookedEmail({
				attendeeName: attendee.name,
				organizationName: organization.data.name,
				meetingAt: input.meetingAt,
				meetingUrl: input.meetingUrl,
				timeZone: input.timeZone,
				changed: input.changed
			})
		});
}

export function buildTrainingCancelledEmail(input: {
	attendeeName: string;
	organizationName: string;
	meetingAt: string;
	timeZone: string | null;
}) {
	const when = formatMeetingTime(input.meetingAt, input.timeZone);
	return {
		subject: `Uplift training cancelled: ${when}`,
		...emailBody(
			[
				`Hi ${greetingName(input.attendeeName)}, the Uplift training for ${input.organizationName} on ${when} is cancelled.`,
				'Uplift will be in touch about a new time.'
			],
			null,
			'Questions? Ask your account owner to write to Uplift in Chat with Uplift.'
		)
	};
}

export async function sendTrainingCancelledEmails(
	client: Client,
	input: {
		organizationId: string;
		eventId: number;
		meetingAt: string;
		timeZone: string | null;
		attendees: TrainingAttendee[];
	}
) {
	const organization = await client
		.from('organizations')
		.select('name')
		.eq('id', input.organizationId)
		.single();
	if (organization.error) throw organization.error;
	for (const attendee of uniqueAttendees(input.attendees))
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_training_cancelled',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-training-cancelled:${input.eventId}:${attendee.email.toLowerCase()}`,
			recipientEmail: attendee.email,
			...buildTrainingCancelledEmail({
				attendeeName: attendee.name,
				organizationName: organization.data.name,
				meetingAt: input.meetingAt,
				timeZone: input.timeZone
			})
		});
}

function uniqueAttendees(attendees: TrainingAttendee[]) {
	const seen = new Set<string>();
	return attendees.filter((attendee) => {
		const email = attendee.email.toLowerCase();
		if (seen.has(email)) return false;
		seen.add(email);
		return true;
	});
}

/**
 * A withdrawal hid a recording link: Jafar's task to restrict or delete the video where it is hosted, since a
 * copied link may still work there. Logged, never thrown, so the client's withdrawal always stands.
 */
export async function tellOwnerToRestrictRecording(
	client: Client,
	input: { organizationId: string; origin: string }
) {
	try {
		const organization = await client
			.from('organizations')
			.select('name')
			.eq('id', input.organizationId)
			.single();
		await raiseOwnerAlert(client, {
			kind: 'setup_training_recording_withdrawn',
			severity: 'attention',
			title: `${organization.data?.name ?? 'A client'} withdrew consent to the training recording`,
			body: 'The link is hidden from them now. Restrict or delete the video where it is hosted, then remove the link from their handover.',
			target: { targetKind: 'organization', targetId: input.organizationId },
			origin: input.origin
		});
	} catch (error) {
		console.error('Could not tell Jafar to restrict the training recording.', error);
	}
}
