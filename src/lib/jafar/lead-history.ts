// A Lead's page and its one history (Jafar business management B2): the words the page, its forms and the API
// share. The history shows notes, contact logged from outside UCRM (an email sent from Gmail, a call, a message,
// and replies), status and next-action changes, and linked Applications, newest first.

import { resolve } from '$app/paths';
import {
	LEAD_SOURCE_LABELS,
	countryName,
	type ContactMethodKind,
	type LeadSource,
	type LeadStatus
} from './leads';
import { CALL_OUTCOMES, CALL_OUTCOME_LABELS, type CallOutcome } from '$lib/pipeline/calls';

// The contractor Brief's call outcomes, so a call reads the same wherever it is logged.
export { CALL_OUTCOMES, CALL_OUTCOME_LABELS, type CallOutcome };

export const CONTACT_DIRECTIONS = ['outbound', 'inbound'] as const;
export type ContactDirection = (typeof CONTACT_DIRECTIONS)[number];

export const CONTACT_DIRECTION_LABELS: Record<ContactDirection, string> = {
	outbound: 'We contacted them',
	inbound: 'They contacted us'
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
	| 'details_changed'
	| 'contact_approved'
	| 'approval_withdrawn'
	| 'sent_back'
	| 'do_not_contact_set'
	| 'do_not_contact_cleared'
	| 'lead_added'
	| 'application_submitted';

export type HistoryEntry = {
	id: string;
	kind: HistoryKind;
	occurred_at: string;
	body: string | null;
	contact_direction: ContactDirection | null;
	contact_channel: ContactChannel | null;
	/** `removed`: the detail was later taken off the Lead; the entry still names it. */
	contact_method: { id: string; kind: ContactMethodKind; value: string; removed?: boolean } | null;
	call_outcome: CallOutcome | null;
	application_id: string | null;
	details: {
		from?: LeadStatus;
		to?: LeadStatus;
		next_action?: string;
		due_on?: string;
		business_name?: string;
		source?: LeadSource;
		changes?: DetailChange[];
		/** B3: the details approved or withdrawn. */
		methods?: Array<{ kind: ContactMethodKind; value: string; whatsapp_permission?: boolean }>;
		/** B3: why it was sent back, or why Do not contact was set or lifted; for a withdrawal, a reason key. */
		reason?: string;
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

export type LeadDoNotContact = { at: string; by: string; reason: string | null };

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
	/** 'first_contact' when approval created the next action; logging outbound contact ticks it off. */
	next_action_kind: 'first_contact' | null;
	do_not_contact: LeadDoNotContact | null;
	/** A linked Application is paid or has its account. */
	is_client: boolean;
	created_by_email: string;
	created_at: string;
	updated_at: string;
};

export type LeadContactMethodDetail = {
	id: string;
	kind: ContactMethodKind;
	value: string;
	found_at: string;
	approved_at: string | null;
	whatsapp_permission: boolean;
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
	return `${resolve('/jafar/prospects')}?application=${encodeURIComponent(applicationId)}`;
}

const OUTBOUND_HEADLINES: Record<ContactChannel, string> = {
	email: 'Emailed them',
	phone: 'Called them',
	text: 'Texted them',
	whatsapp: 'Messaged them on WhatsApp',
	linkedin: 'Messaged them on LinkedIn',
	instagram: 'Messaged them on Instagram',
	facebook: 'Messaged them on Facebook',
	contact_form: 'Sent their website contact form',
	in_person: 'Met them in person',
	other: 'Contacted them'
};

const INBOUND_HEADLINES: Record<ContactChannel, string> = {
	email: 'They emailed',
	phone: 'They called',
	text: 'They texted',
	whatsapp: 'They messaged on WhatsApp',
	linkedin: 'They messaged on LinkedIn',
	instagram: 'They messaged on Instagram',
	facebook: 'They messaged on Facebook',
	contact_form: 'They used our contact form',
	in_person: 'They came to us in person',
	other: 'They got in touch'
};

/** "Emailed them", "They called": the line a logged contact reads as in the history. */
export function contactHeadline(direction: ContactDirection, channel: ContactChannel) {
	return (direction === 'outbound' ? OUTBOUND_HEADLINES : INBOUND_HEADLINES)[channel];
}

// --- B2b: a Lead's details edited ----------------------------------------------------------------------------

/** One change in a 'details_changed' entry, as the database records it. */
export type DetailChange =
	| { field: 'fit_notes' }
	| {
			field:
				| 'business_name'
				| 'country_code'
				| 'trade'
				| 'website'
				| 'contact_name'
				| 'source'
				| 'source_detail';
			from: string | null;
			to: string | null;
	  }
	| {
			field: 'contact_method';
			action: 'added' | 'changed' | 'removed';
			kind: ContactMethodKind;
			value: string;
			from?: string;
			to?: string;
			found_at_changed?: boolean;
	  };

const FIELD_NAMES = {
	business_name: 'Business name',
	country_code: 'Country',
	trade: 'Trade',
	website: 'Website',
	contact_name: 'Contact person',
	source: 'How you found them',
	source_detail: 'Source details'
} as const;

/** The words for one stored value: a country or source by its name, anything else as typed. */
function fieldValue(field: keyof typeof FIELD_NAMES, value: string) {
	if (field === 'country_code') return countryName(value);
	if (field === 'source') return LEAD_SOURCE_LABELS[value as LeadSource] ?? value;
	return value;
}

// How a detail reads inside a sentence: "Added WhatsApp number +44…".
const DETAIL_WORDS: Record<ContactMethodKind, string> = {
	email: 'email',
	phone: 'phone number',
	whatsapp: 'WhatsApp number',
	instagram: 'Instagram profile',
	facebook: 'Facebook page',
	linkedin: 'LinkedIn profile',
	contact_form: 'contact form link',
	other: 'contact detail'
};

/** "Email changed from info@smithplumbng.co.uk to info@smithplumbing.co.uk": one line per change. */
export function detailChangeLine(change: DetailChange): string {
	if (change.field === 'fit_notes') return 'Updated why they may fit';
	if (change.field === 'contact_method') {
		const words = DETAIL_WORDS[change.kind] ?? 'contact detail';
		if (change.action === 'added') return `Added ${words} ${change.value}`;
		if (change.action === 'removed') return `Removed ${words} ${change.value}`;
		const where = change.found_at_changed ? ', and where it was found' : '';
		if (change.from && change.to)
			return `${words[0].toUpperCase()}${words.slice(1)} changed from ${change.from} to ${change.to}${where}`;
		return `Updated where the ${words} ${change.value} was found`;
	}
	const name = FIELD_NAMES[change.field];
	if (!change.from && change.to) return `${name} added: ${fieldValue(change.field, change.to)}`;
	if (change.from && !change.to)
		return `${name} removed (was ${fieldValue(change.field, change.from)})`;
	return `${name} changed from ${fieldValue(change.field, change.from ?? '')} to ${fieldValue(change.field, change.to ?? '')}`;
}

// --- B3: approving who to contact ------------------------------------------------------------------------------

const APPROVAL_METHOD_WORDS: Record<ContactMethodKind, string> = {
	email: 'Email',
	phone: 'Phone',
	whatsapp: 'WhatsApp',
	instagram: 'Instagram',
	facebook: 'Facebook',
	linkedin: 'LinkedIn',
	contact_form: 'Contact form',
	other: 'Other'
};

/** "Email info@smithplumbing.co.uk", with "(they asked for WhatsApp)" where that permission was recorded. */
export function approvalMethodLine(method: {
	kind: ContactMethodKind;
	value: string;
	whatsapp_permission?: boolean;
}) {
	const permission = method.whatsapp_permission ? ' (they asked to talk on WhatsApp)' : '';
	return `${APPROVAL_METHOD_WORDS[method.kind] ?? 'Contact'} ${method.value}${permission}`;
}

const WITHDRAWN_BECAUSE: Record<string, string> = {
	details_changed: 'because the detail changed',
	sent_back: 'because the Lead was sent back',
	do_not_contact: 'because they asked not to be contacted',
	status_changed: 'because the status changed'
};

/** The line under an "Approval withdrawn" entry. */
export function withdrawnBecause(reason: string | undefined) {
	return (reason && WITHDRAWN_BECAUSE[reason]) ?? '';
}
