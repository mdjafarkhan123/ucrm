// A Lead's page and its one history (Jafar business management B2): the words the page, its forms and the API
// share. The history shows notes, contact logged from outside UCRM (an email sent from Gmail, a call, a message,
// and replies), status and next-action changes, and linked Applications, newest first.

import type { ContactMethodKind, LeadSource, LeadStatus } from './leads';
import { CALL_OUTCOMES, CALL_OUTCOME_LABELS, type CallOutcome } from '$lib/pipeline/calls';

// The contractor Brief's call outcomes, so a call reads the same wherever it is logged.
export { CALL_OUTCOMES, CALL_OUTCOME_LABELS, type CallOutcome };

export const CONTACT_DIRECTIONS = ['outbound', 'inbound'] as const;
export type ContactDirection = (typeof CONTACT_DIRECTIONS)[number];

export const CONTACT_DIRECTION_LABELS: Record<ContactDirection, string> = {
	outbound: 'We contacted them',
	inbound: 'They replied or contacted us'
};

export const CONTACT_CHANNELS = [
	'email',
	'phone',
	'text',
	'whatsapp',
	'linkedin',
	'instagram',
	'facebook',
	'contact_form',
	'in_person',
	'other'
] as const;
export type ContactChannel = (typeof CONTACT_CHANNELS)[number];

export const CONTACT_CHANNEL_LABELS: Record<ContactChannel, string> = {
	email: 'Email',
	phone: 'Phone call',
	text: 'Text message',
	whatsapp: 'WhatsApp',
	linkedin: 'LinkedIn',
	instagram: 'Instagram',
	facebook: 'Facebook',
	contact_form: 'Website contact form',
	in_person: 'In person',
	other: 'Other'
};

/** Which saved contact details a channel can have used: a text or a call goes to a phone number. */
export const CHANNEL_METHOD_KINDS: Record<ContactChannel, readonly ContactMethodKind[]> = {
	email: ['email'],
	phone: ['phone', 'whatsapp'],
	text: ['phone', 'whatsapp'],
	whatsapp: ['whatsapp', 'phone'],
	linkedin: ['linkedin'],
	instagram: ['instagram'],
	facebook: ['facebook'],
	contact_form: ['contact_form'],
	in_person: [],
	other: ['other']
};

/** Only a call we made says how it went; the database holds the same rule. */
export function takesCallOutcome(channel: ContactChannel, direction: ContactDirection) {
	return channel === 'phone' && direction === 'outbound';
}

export const HISTORY_BODY_MAX = 4000;
export const HISTORY_PAGE_SIZE = 50;
// A clock a few minutes fast on the phone that logs it should not turn "just now" into an error.
export const CONTACT_FUTURE_SKEW_MS = 5 * 60 * 1000;

export type HistoryKind =
	| 'note'
	| 'contact'
	| 'status_changed'
	| 'next_action_set'
	| 'next_action_done'
	| 'next_action_cleared'
	| 'application_linked'
	| 'application_unlinked'
	| 'lead_added'
	| 'application_submitted';

export type HistoryEntry = {
	id: string;
	kind: HistoryKind;
	occurred_at: string;
	body: string | null;
	contact_direction: ContactDirection | null;
	contact_channel: ContactChannel | null;
	contact_method: { id: string; kind: ContactMethodKind; value: string } | null;
	call_outcome: CallOutcome | null;
	application_id: string | null;
	details: {
		from?: LeadStatus;
		to?: LeadStatus;
		next_action?: string;
		due_on?: string;
		business_name?: string;
		source?: LeadSource;
	} | null;
	/** Who did it, as a name: "Jafar", a teammate, or their email. Null when nobody did (an Application arriving). */
	actor: string | null;
	edited_at: string | null;
};

export type HistoryPage = { entries: HistoryEntry[]; next_cursor: string | null };

/** Notes and logged contact belong to a person and can be changed; the rest is what the app recorded. */
export function isEditableEntry(entry: Pick<HistoryEntry, 'kind'>) {
	return entry.kind === 'note' || entry.kind === 'contact';
}

export const APPLICATION_STAGE_LABELS: Record<string, string> = {
	new: 'New',
	needs_attention: 'Needs attention',
	payment_confirmed: 'Payment confirmed',
	account_created: 'Account created',
	not_proceeding: 'Not proceeding'
};

export type LinkedApplication = {
	id: string;
	business_name: string;
	main_contact_name: string;
	main_contact_email: string;
	stage: string;
	submitted_at: string;
};

export type ApplicationCandidate = LinkedApplication & {
	linked_to: { id: string; business_name: string } | null;
};

export type LeadDetail = {
	id: string;
	business_name: string;
	country_code: string;
	trade: string;
	source: LeadSource;
	source_detail: string | null;
	website: string | null;
	website_host: string | null;
	contact_name: string | null;
	fit_notes: string | null;
	lead_status: LeadStatus;
	next_action: string | null;
	next_action_due_on: string | null;
	created_by_email: string;
	created_at: string;
	updated_at: string;
};

export type LeadContactMethodDetail = {
	id: string;
	kind: ContactMethodKind;
	value: string;
	found_at: string;
};

export type LeadPage = {
	lead: LeadDetail;
	contact_methods: LeadContactMethodDetail[];
	applications: LinkedApplication[];
	last_contacted_at: string | null;
	last_heard_from_at: string | null;
	history: HistoryPage;
};

/** The link that opens one Application in the Applications screen's review drawer. */
export function applicationHref(applicationId: string) {
	return `/jafar/prospects?application=${encodeURIComponent(applicationId)}`;
}
