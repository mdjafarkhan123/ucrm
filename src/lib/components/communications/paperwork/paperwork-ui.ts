import type {
	PaperworkDetail,
	PaperworkStatus,
	PaperworkSummary
} from '$lib/communications/number-paperwork';
import type { NumberType } from '$lib/communications/sms-number-shop';
import { countryDisplayName } from '$lib/settings/country-names';
import { chosenDocumentKinds } from '$lib/communications/number-paperwork';
import flagIcon from '@tabler/icons/outline/flag.svg?raw';
import buildingIcon from '@tabler/icons/outline/building.svg?raw';
import userIcon from '@tabler/icons/outline/user.svg?raw';
import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
import fileXIcon from '@tabler/icons/outline/file-x.svg?raw';

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
	icon: string;
	tone: string;
	label: string;
	value: string;
	step: 'start' | 'details' | 'documents';
	/** A document the phone company sent back. */
	needsFix?: boolean;
};

/** What the set says, as the Check step and the opened set read it back. */
export function paperworkFacts(detail: PaperworkDetail, businessName: string): FactRow[] {
	const answers = detail.answers;
	const person = [answers.first_name, answers.last_name].filter(Boolean).join(' ');
	const rows: FactRow[] = [
		{
			key: 'kind',
			icon: flagIcon,
			tone: 'informative',
			label: 'Country and kind',
			value: setTitle(detail),
			step: 'start'
		}
	];
	if (detail.end_user_type === 'business') {
		const registered = [
			answers.business_registration_number,
			registrationPlace(answers.business_registration_identifier)
		]
			.filter(Boolean)
			.join(', ');
		rows.push({
			key: 'owner',
			icon: buildingIcon,
			tone: 'conversation',
			label: 'Who owns the numbers',
			value: ['A business', answers.business_name || businessName, registered]
				.filter(Boolean)
				.join(' · '),
			step: 'details'
		});
		const contact = [person, answers.email, answers.phone_number].filter(Boolean).join(' · ');
		if (contact) {
			rows.push({
				key: 'person',
				icon: userIcon,
				tone: 'informative',
				label: 'Person in charge',
				value: contact,
				step: 'details'
			});
		}
	} else {
		rows.push({
			key: 'owner',
			icon: userIcon,
			tone: 'informative',
			label: 'Who owns the numbers',
			value: ['Just me', person, answers.email].filter(Boolean).join(' · '),
			step: 'details'
		});
	}
	if (detail.form.needsAddress && detail.address) {
		rows.push({
			key: 'address',
			icon: mapPinIcon,
			tone: 'client',
			label: detail.end_user_type === 'business' ? 'Business address' : 'Home address',
			value: addressLine(detail.address),
			step: 'details'
		});
	}
	const fixed = new Set(
		detail.fixes
			.filter((fix) => fix.step === 'documents')
			.map((fix) => fix.target.split(':')[1])
	);
	for (const kind of chosenDocumentKinds(detail.form.requirements, detail.document_choices)) {
		if (!kind.needsFile) continue;
		const file = detail.documents.find((document) => document.document_type === kind.documentType)
			?.file;
		const needsFix = fixed.has(kind.documentType);
		rows.push({
			key: `document-${kind.documentType}`,
			icon: needsFix ? fileXIcon : fileCheckIcon,
			tone: needsFix ? 'critical' : 'success',
			label: 'Documents',
			value: [kind.label, file && file.state !== 'deleted' ? file.name : 'Not added yet']
				.filter(Boolean)
				.join(' · '),
			step: 'documents',
			needsFix
		});
	}
	return rows;
}

function registrationPlace(identifier: string | undefined): string {
	if (!identifier) return '';
	const country = identifier.split(':')[0];
	if (country === 'UK') return countryName('GB');
	return /^[A-Z]{2}$/.test(country) ? countryName(country) : '';
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

const FIELD_HINTS: Record<string, string> = {
	phone_number: 'A real business or mobile line, not a number from a texting company.'
};

/** A quiet line under a field the phone company is strict about. */
export function fieldHint(name: string): string {
	return FIELD_HINTS[name] ?? '';
}

const FIELD_PLACEHOLDERS: Record<string, string> = {
	business_registration_number: 'e.g. BC1234567',
	business_website: 'e.g. yourbusiness.com',
	email: 'name@yourbusiness.com',
	phone_number: '+447700900123'
};

export function fieldPlaceholder(field: { name: string; kind: string }): string {
	return FIELD_PLACEHOLDERS[field.name] ?? (field.kind === 'phone' ? '+447700900123' : '');
}

/** "2.2 MB", "640 KB". */
export function fileSize(bytes: number): string {
	if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
	return `${bytes > 0 ? Math.max(1, Math.round(bytes / 1024)) : 0} KB`;
}

/** "a United Kingdom mobile number", "an Australia mobile number". */
export function withArticle(words: string): string {
	return `${/^[aeiou]/i.test(words) ? 'an' : 'a'} ${words}`;
}
