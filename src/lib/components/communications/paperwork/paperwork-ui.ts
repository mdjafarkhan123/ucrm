import type {
	PaperworkDetail,
	PaperworkStatus,
	PaperworkSummary
} from '$lib/communications/number-paperwork';
import type { NumberType } from '$lib/communications/sms-number-shop';
import { countryDisplayName } from '$lib/settings/country-names';

// Words and pills the Number paperwork pages share (design skill `layout.md` → Number paperwork).

export type StatusTone = 'inactive' | 'warning' | 'success' | 'critical' | 'informative';

const STATUS: Record<PaperworkStatus, { tone: StatusTone; label: string }> = {
	draft: { tone: 'inactive', label: 'Draft' },
	sending: { tone: 'informative', label: 'Sending' },
	under_review: { tone: 'warning', label: 'Under review' },
	approved: { tone: 'success', label: 'Approved' },
	needs_fix: { tone: 'critical', label: 'Needs a fix' }
};

export function paperworkStatus(status: PaperworkStatus) {
	return STATUS[status];
}

const KIND_NAMES: Record<NumberType, string> = {
	local: 'Local numbers',
	mobile: 'Mobile numbers',
	national: 'National numbers',
	toll_free: 'Toll-free numbers'
};

const KIND_WORDS: Record<NumberType, string> = {
	local: 'local',
	mobile: 'mobile',
	national: 'national',
	toll_free: 'toll-free'
};

export function kindName(type: NumberType): string {
	return KIND_NAMES[type];
}

/** "mobile", for a sentence such as "a UK mobile number". */
export function kindWord(type: NumberType): string {
	return KIND_WORDS[type];
}

export function countryName(code: string): string {
	return countryDisplayName(code);
}

/** "United Kingdom · Mobile numbers" */
export function setTitle(set: Pick<PaperworkSummary, 'country_code' | 'number_type'>): string {
	return `${countryName(set.country_code)} · ${kindName(set.number_type)}`;
}

const SHORT_DATE = new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric' });
const LONG_DATE = new Intl.DateTimeFormat('en', {
	month: 'short',
	day: 'numeric',
	year: 'numeric'
});

export function shortDate(iso: string | null): string {
	return iso ? SHORT_DATE.format(new Date(iso)) : '';
}

export function longDate(iso: string | null): string {
	return iso ? LONG_DATE.format(new Date(iso)) : '';
}

function isToday(iso: string): boolean {
	return new Date(iso).toDateString() === new Date().toDateString();
}

/** The quiet line under a set's name: who owns it and where it stands. */
export function setMeta(set: PaperworkSummary): string {
	const owner = set.end_user_type === 'business' ? 'Business' : 'Just me';
	switch (set.status) {
		case 'draft':
			return `${owner} · ${isToday(set.updated_at) ? 'Started today' : `Started ${shortDate(set.updated_at)}`}`;
		case 'sending':
			return `${owner} · Sending now`;
		case 'under_review':
			return `${owner} · Sent ${shortDate(set.submitted_at)} · usually checked within 5 business days`;
		case 'approved':
			return `${owner} · Approved ${shortDate(set.decided_at)} · works for more ${countryName(set.country_code)} numbers`;
		case 'needs_fix':
			return `${owner} · Sent ${shortDate(set.submitted_at ?? set.updated_at)}`;
	}
}

export type FactRow = {
	key: string;
	label: string;
	value: string;
	step: 'details' | 'documents' | 'start';
};

/** What the set says, as the Check step and the opened set read it back. */
export function factRows(detail: PaperworkDetail, businessName: string): FactRow[] {
	const rows: FactRow[] = [
		{ key: 'kind', label: 'Country and kind', value: setTitle(detail), step: 'start' }
	];
	const answers = detail.answers;
	const person = [answers.first_name, answers.last_name].filter(Boolean).join(' ');
	if (detail.end_user_type === 'business') {
		const registration = [answers.business_registration_number].filter(Boolean).join('');
		rows.push({
			key: 'owner',
			label: 'Who owns the numbers',
			value: ['A business', businessName, registration].filter(Boolean).join(' · '),
			step: 'details'
		});
	} else {
		rows.push({
			key: 'owner',
			label: 'Who owns the numbers',
			value: `Just me · ${person}`,
			step: 'details'
		});
	}
	const contact = [person, answers.email, answers.phone_number].filter(Boolean).join(' · ');
	if (contact && detail.end_user_type === 'business') {
		rows.push({ key: 'person', label: 'Person in charge', value: contact, step: 'details' });
	}
	if (detail.form.needsAddress && detail.address) {
		rows.push({
			key: 'address',
			label: detail.end_user_type === 'business' ? 'Business address' : 'Home address',
			value: addressLine(detail.address),
			step: 'details'
		});
	}
	return rows;
}

export function addressLine(address: PaperworkDetail['address']): string {
	if (!address) return '';
	return [
		[address.street, address.street_secondary].filter(Boolean).join(', '),
		address.city,
		[address.region, address.postal_code].filter(Boolean).join(' '),
		address.country_code ? countryName(address.country_code) : ''
	]
		.filter(Boolean)
		.join(', ');
}
