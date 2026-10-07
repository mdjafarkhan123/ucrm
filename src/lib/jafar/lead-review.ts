// Approving who to contact (Jafar business management B3): the words the review queue, the Lead page and the API
// share. Approval belongs to one contact detail; nothing here sends a message. Jafar approves a detail, a
// first-contact task appears, and the person contacts the business themselves and logs it.

import type { ContactMethodKind, LeadSource } from './leads';

export type ReviewContactMethod = {
	id: string;
	kind: ContactMethodKind;
	value: string;
	found_at: string;
};

export type ReviewLead = {
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
	created_at: string;
	/** Who prepared it: a teammate's name, or the email of whoever added it. */
	prepared_by: string;
	do_not_contact: { at: string; reason: string | null } | null;
	is_client: boolean;
	contact_methods: ReviewContactMethod[];
	contact: {
		outbound_count: number;
		inbound_count: number;
		last_outbound_at: string | null;
		last_inbound_at: string | null;
	};
	/** Why it was last sent back, if it ever was. */
	last_sent_back: string | null;
};

export type ReviewQueuePage = {
	leads: ReviewLead[];
	next_cursor: string | null;
	/** Every Lead ready for review, not just this page. */
	total: number;
};

export type LeadExclusion = 'do_not_contact' | 'client' | 'no_contact_details';

/**
 * Why this business cannot be approved at all, or null when it can. Checked in this order: an opt-out is the
 * strongest reason, and the database refuses the first two whatever the screen shows.
 */
export function leadExclusion(
	lead: Pick<ReviewLead, 'do_not_contact' | 'is_client' | 'contact_methods'>
): LeadExclusion | null {
	if (lead.do_not_contact) return 'do_not_contact';
	if (lead.is_client) return 'client';
	if (lead.contact_methods.length === 0) return 'no_contact_details';
	return null;
}

export const LEAD_EXCLUSION_TEXT: Record<LeadExclusion, { title: string; detail: string }> = {
	do_not_contact: {
		title: 'Asked not to be contacted',
		detail:
			'Nobody at Uplift may contact this business. Mark it Unsuitable or keep it for the record.'
	},
	client: {
		title: 'Already a client',
		detail:
			'Their Application is paid or their account exists. Look after them through Onboarding and Support.'
	},
	no_contact_details: {
		title: 'No way to reach them yet',
		detail: 'Add an email, phone number or profile from their own website first.'
	}
};

/**
 * WhatsApp may only be used once the business has asked to talk there (WhatsApp Business Messaging Policy), so
 * its number needs that permission ticked before it can be approved.
 */
export function needsPermission(kind: ContactMethodKind) {
	return kind === 'whatsapp';
}

/** Information worth having before a first contact, but not required for approval. */
export function missingInformation(
	lead: Pick<ReviewLead, 'contact_name' | 'website' | 'fit_notes'>
): string[] {
	const missing: string[] = [];
	if (!lead.fit_notes) missing.push('Why they may fit');
	if (!lead.contact_name) missing.push('Who to ask for');
	if (!lead.website) missing.push('Their website');
	return missing;
}

/** "Never contacted", "Contacted 2 times · they replied": earlier contact, in one line. */
export function previousContactLine(contact: ReviewLead['contact']): string {
	const { outbound_count: out, inbound_count: inbound } = contact;
	if (out === 0 && inbound === 0) return 'No contact yet';
	const parts: string[] = [];
	if (out > 0) parts.push(out === 1 ? 'Contacted once' : `Contacted ${out} times`);
	if (inbound > 0)
		parts.push(inbound === 1 ? 'they got in touch once' : `they got in touch ${inbound} times`);
	const line = parts.join(' · ');
	return line[0].toUpperCase() + line.slice(1);
}

/** The details a reviewer can tick: everything except where the whole business is excluded. */
export function approvableMethods(lead: ReviewLead): ReviewContactMethod[] {
	return leadExclusion(lead) ? [] : lead.contact_methods;
}

/** Today's date where the reviewer is, as the API expects it (YYYY-MM-DD). */
export function localToday(now = new Date()) {
	const month = String(now.getMonth() + 1).padStart(2, '0');
	const day = String(now.getDate()).padStart(2, '0');
	return `${now.getFullYear()}-${month}-${day}`;
}

/** The reason an approval was withdrawn, for the Lead's history. */
export const APPROVAL_WITHDRAWN_REASONS: Record<string, string> = {
	details_changed: 'the detail changed',
	sent_back: 'it was sent back',
	do_not_contact: 'they asked not to be contacted',
	status_changed: 'the status changed'
};
