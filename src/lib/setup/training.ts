// Client onboarding E6: training and handover (plan §6). Once the approved system has launched, Jafar marks it Live;
// from Ready for Uplift onward the client's owners and administrators give training details, and an owner may say
// they don't need training. Jafar books a time and a meeting link, adds a recording link only while the client
// consents, writes the handover, and marks the project delivered once nothing blocks it. Industry reference: client
// tasks and completion milestones in GUIDEcx and Rocketlane. Mirrors
// supabase/migrations/20261104090000_setup_training_handover.sql.

export const TRAINING_ATTENDEES_MAX = 10;
export const TRAINING_NAME_MAX = 120;
export const TRAINING_ROLE_MAX = 120;
export const TRAINING_TEXT_MAX = 1000;
export const TRAINING_TASKS_MAX = 2000;
export const HANDOVER_SUMMARY_MAX = 4000;
export const HANDOVER_GUIDES_MAX = 20;
export const HANDOVER_GUIDE_TITLE_MAX = 120;
export const LINK_MAX = 500;

/** The dashboard card shows Project delivered this many days, then hides. */
export const DELIVERED_CARD_DAYS = 14;

export type TrainingAttendee = { name: string; role: string; email: string };

/** The training record as the client's owners and administrators read it. The recording link is never here. */
export type SetupTraining = {
	attendees: TrainingAttendee[];
	time_zone: string | null;
	preferred_times: string | null;
	needs: string | null;
	top_tasks: string | null;
	details_updated_at: string | null;
	details_updated_by_name: string | null;
	recording_consent: boolean | null;
	consent_changed_at: string | null;
	consent_changed_by_name: string | null;
	skipped_at: string | null;
	skipped_by_name: string | null;
	meeting_at: string | null;
	meeting_url: string | null;
	booked_at: string | null;
};

export const TRAINING_COLUMNS =
	'attendees, time_zone, preferred_times, needs, top_tasks, details_updated_at, details_updated_by_name, recording_consent, consent_changed_at, consent_changed_by_name, skipped_at, skipped_by_name, meeting_at, meeting_url, booked_at';

export type HandoverGuide = { title: string; url: string };

export type SetupHandover = {
	live_at: string | null;
	live_version: number | null;
	access_summary: string | null;
	guides: HandoverGuide[];
	updated_at: string | null;
	delivered_at: string | null;
};

export const HANDOVER_COLUMNS =
	'live_at, live_version, access_summary, guides, updated_at, delivered_at';

export const HANDOVER_EVENT_KINDS = [
	'live',
	'delivered',
	'handover_updated',
	'training_details',
	'training_skipped',
	'training_booked',
	'training_changed',
	'training_cancelled',
	'consent_given',
	'consent_withdrawn',
	'recording_added',
	'recording_removed'
] as const;
export type HandoverEventKind = (typeof HANDOVER_EVENT_KINDS)[number];

export type HandoverEvent = {
	id: number;
	kind: HandoverEventKind;
	happened_at: string;
	actor_kind: 'uplift' | 'client';
	actor_name: string;
	detail: { meeting_at?: string; previous_meeting_at?: string | null; version?: number };
};

/** Where training stands. */
export type TrainingStatus = 'not_started' | 'details_given' | 'booked' | 'skipped';

export function trainingStatus(training: SetupTraining | null): TrainingStatus {
	if (training?.meeting_at) return 'booked';
	if (training?.skipped_at) return 'skipped';
	if (training && training.attendees.length > 0) return 'details_given';
	return 'not_started';
}

/** The client may change the details until Jafar books, and not after an owner said no training. */
export const trainingDetailsOpen = (training: SetupTraining | null) =>
	!training?.meeting_at && !training?.skipped_at;

export type DeliveryBlocker = 'not_live' | 'training' | 'access_summary' | 'guides';

/** What still stands between Live and Delivered. Mirrors private.setup_delivery_blockers. */
export function deliveryBlockers(
	handover: SetupHandover | null,
	training: SetupTraining | null
): DeliveryBlocker[] {
	const blockers: DeliveryBlocker[] = [];
	if (!handover?.live_at) blockers.push('not_live');
	if (!training?.meeting_at && !training?.skipped_at) blockers.push('training');
	if (!handover?.access_summary) blockers.push('access_summary');
	if (!handover?.guides.length) blockers.push('guides');
	return blockers;
}

export const DELIVERY_BLOCKER_LABEL: Record<DeliveryBlocker, string> = {
	not_live: 'Mark the system live',
	training: 'Book the training, or the owner says they don’t need it',
	access_summary: 'Write the access and ownership summary',
	guides: 'Add at least one guide'
};

/** A history line, as the client reads it: Uplift's actions are Uplift's, not a person's email. */
export function handoverEventText(event: HandoverEvent, formatMoment: (value: string) => string) {
	const who = event.actor_kind === 'uplift' ? 'Uplift' : event.actor_name;
	switch (event.kind) {
		case 'live':
			return `${who} marked your system live${event.detail.version ? ` (preview version ${event.detail.version})` : ''}`;
		case 'delivered':
			return `${who} marked your project delivered`;
		case 'handover_updated':
			return `${who} updated the handover pack`;
		case 'training_details':
			return `${who} gave the training details`;
		case 'training_skipped':
			return `${who} said you don’t need training`;
		case 'training_booked':
			return `${who} booked training for ${event.detail.meeting_at ? formatMoment(event.detail.meeting_at) : 'a set time'}`;
		case 'training_changed':
			return `${who} moved training to ${event.detail.meeting_at ? formatMoment(event.detail.meeting_at) : 'a new time'}`;
		case 'training_cancelled':
			return `${who} cancelled the training${event.detail.meeting_at ? ` on ${formatMoment(event.detail.meeting_at)}` : ''}`;
		case 'consent_given':
			return `${who} agreed to a training recording`;
		case 'consent_withdrawn':
			return `${who} withdrew consent to a training recording`;
		case 'recording_added':
			return `${who} added the training recording`;
		case 'recording_removed':
			return `${who} removed the training recording`;
	}
}

/** A meeting time in the time zone the client gave, with the zone named. */
export function formatMeetingTime(value: string, timeZone: string | null) {
	const zone = timeZone || 'UTC';
	try {
		return new Intl.DateTimeFormat('en-GB', {
			weekday: 'long',
			day: 'numeric',
			month: 'long',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit',
			timeZone: zone,
			timeZoneName: 'short'
		}).format(new Date(value));
	} catch {
		return new Date(value).toUTCString();
	}
}
