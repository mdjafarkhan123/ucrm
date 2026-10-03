// Every question the client setup wizard asks, in one place. A fact is asked once and stored under its
// key (docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md), so the page, the server's
// validation and the task list's progress all read this same list and can never disagree about what a
// section contains. Adding a question is a new entry here, not a database change.

import { COMMON_CURRENCIES } from '$lib/settings/currencies';
import { TRADES } from '$lib/settings/trades';
import { parseSetupHours, parseSetupHoursExceptions } from '$lib/setup/hours';

export type SetupAvailability = 'have' | 'not_yet' | 'need_help';

export type SetupFactKind =
	| 'text'
	| 'longtext'
	| 'email'
	| 'phone'
	| 'choice'
	/** A list plus "Other", saved as the words themselves. */
	| 'choice_other'
	/** Saved as the ISO country code. */
	| 'country'
	| 'timezone'
	/** The normal week. Saved as JSON — see `$lib/setup/hours`. */
	| 'hours'
	/** Dated days that differ from the normal week. Saved as JSON. */
	| 'hours_exceptions';

export type SetupFact = {
	key: string;
	label: string;
	hint?: string;
	kind: SetupFactKind;
	required: boolean;
	maxLength?: number;
	options?: { value: string; label: string }[];
	/** Shows a short list of choices as radio buttons instead of a dropdown. */
	layout?: 'radio';
	/** `choice_other`: the label of the box that appears when "Other" is picked. */
	otherLabel?: string;
	/** Offers "I don't have this yet" and "I need Uplift's help" beside the answer. */
	canDefer?: boolean;
};

export type SetupGroup = { title: string; hint: string; facts: SetupFact[] };

const LANGUAGES = [
	'English',
	'French',
	'German',
	'Spanish',
	'Italian',
	'Dutch',
	'Portuguese',
	'Polish',
	'Swedish',
	'Danish',
	'Norwegian',
	'Finnish',
	'Other'
];

const YES_NO = (yes: string, no: string) => [
	{ value: 'yes', label: yes },
	{ value: 'no', label: no }
];

export type SetupSection = {
	key: string;
	title: string;
	description: string;
	groups: SetupGroup[];
};

export const SETUP_SECTIONS: SetupSection[] = [
	{
		key: 'business',
		title: 'Your business',
		description: 'The name, people and contact details Uplift builds everything else around.',
		groups: [
			{
				title: 'Business identity',
				hint: 'How your business is known. Plain facts are enough — Uplift writes the polished wording.',
				facts: [
					{
						key: 'business.public_name',
						label: 'Business name customers know you by',
						hint: 'Exactly as it appears on your van, cards or signs.',
						kind: 'text',
						required: true,
						maxLength: 120
					},
					{
						key: 'business.legal_name',
						label: 'Legal name, if different',
						hint: 'Leave empty if it is the same as the name above.',
						kind: 'text',
						required: false,
						maxLength: 160
					},
					{
						key: 'business.trade',
						label: 'Trade',
						kind: 'choice_other',
						required: true,
						maxLength: 120,
						options: TRADES.map((trade) => ({ value: trade, label: trade })),
						otherLabel: 'Your trade'
					},
					{
						key: 'business.type',
						label: 'Type of business',
						kind: 'choice',
						required: true,
						options: [
							{ value: 'sole_trader', label: 'Sole trader / self-employed' },
							{ value: 'partnership', label: 'Partnership' },
							{ value: 'company', label: 'Limited company, LLC or corporation' },
							{ value: 'other', label: 'Something else' },
							{ value: 'unsure', label: "I'm not sure" }
						]
					}
				]
			},
			{
				title: 'Who Uplift talks to',
				hint: 'The person we contact during setup, and who gives the final go-ahead before launch.',
				facts: [
					{
						key: 'business.contact_name',
						label: 'Main contact name',
						kind: 'text',
						required: true,
						maxLength: 120
					},
					{
						key: 'business.contact_email',
						label: 'Main contact email',
						kind: 'email',
						required: true
					},
					{
						key: 'business.contact_phone',
						label: 'Main contact phone',
						kind: 'phone',
						required: true
					},
					{
						key: 'business.approver_name',
						label: 'Final approver name, if someone else',
						hint: 'Leave empty if the main contact approves the finished work.',
						kind: 'text',
						required: false,
						maxLength: 120
					},
					{
						key: 'business.approver_email',
						label: 'Final approver email',
						kind: 'email',
						required: false
					}
				]
			},
			{
				title: 'How customers reach you',
				hint: 'The phone and email shown to customers. No business number or address yet? Say so and Uplift will help.',
				facts: [
					{
						key: 'business.public_phone',
						label: 'Public phone number',
						kind: 'phone',
						required: true,
						canDefer: true
					},
					{
						key: 'business.public_email',
						label: 'Public email address',
						kind: 'email',
						required: true,
						canDefer: true
					}
				]
			},
			{
				title: 'Where you’re based',
				hint: 'Where you run the business from — your home is fine. It stays private unless you say otherwise.',
				facts: [
					{
						key: 'business.country',
						label: 'Country',
						kind: 'country',
						required: true
					},
					{
						key: 'business.address_line1',
						label: 'Street address',
						kind: 'text',
						required: true,
						maxLength: 160,
						canDefer: true
					},
					{
						key: 'business.address_line2',
						label: 'Flat, unit or suite, if any',
						kind: 'text',
						required: false,
						maxLength: 160
					},
					{
						key: 'business.address_city',
						label: 'Town or city',
						kind: 'text',
						required: true,
						maxLength: 120
					},
					{
						key: 'business.address_region',
						label: 'State, province or county',
						kind: 'text',
						required: false,
						maxLength: 120
					},
					{
						key: 'business.address_postal_code',
						label: 'Postcode or ZIP code',
						kind: 'text',
						required: true,
						maxLength: 20
					},
					{
						key: 'business.address_customers_visit',
						label: 'Do customers come to this address?',
						hint: 'A shop, showroom or office counts. A home you only work out from does not.',
						kind: 'choice',
						layout: 'radio',
						required: true,
						options: YES_NO('Yes, customers visit', 'No, I go to them')
					},
					{
						key: 'business.address_public',
						label: 'Can this address be shown publicly?',
						hint: 'If you keep it private, customers only see your town and the areas you cover.',
						kind: 'choice',
						layout: 'radio',
						required: true,
						options: YES_NO('Yes, show the full address', 'No, keep it private')
					}
				]
			},
			{
				title: 'Language, time and money',
				hint: 'How words, times and prices appear across your system. Check each one — none of them becomes your default until you have confirmed it here.',
				facts: [
					{
						key: 'business.language',
						label: 'Language your customers read',
						hint: 'Uplift writes your website and customer messages in this language.',
						kind: 'choice_other',
						required: true,
						maxLength: 60,
						options: LANGUAGES.map((language) => ({ value: language, label: language })),
						otherLabel: 'Your language'
					},
					{
						key: 'business.timezone',
						label: 'Time zone',
						hint: 'Sets the times on your schedule, bookings and reminders.',
						kind: 'timezone',
						required: true
					},
					{
						key: 'business.currency',
						label: 'Currency you charge in',
						hint: 'Used on every quote, invoice and payment.',
						kind: 'choice',
						required: true,
						options: COMMON_CURRENCIES.map((currency) => ({
							value: currency.code,
							label: `${currency.code} — ${currency.label}`
						}))
					}
				]
			},
			{
				title: 'Opening hours',
				hint: 'When customers can reach you. Uplift uses these on your website, your Google profile and your reminders.',
				facts: [
					{
						key: 'business.hours',
						label: 'Normal weekly hours',
						kind: 'hours',
						required: true
					},
					{
						key: 'business.hours_exceptions',
						label: 'Holidays and one-off days',
						hint: 'Days in the next year when you are closed or keep different hours — public holidays, Christmas week, a planned break.',
						kind: 'hours_exceptions',
						required: false
					},
					{
						key: 'business.hours_seasonal',
						label: 'Seasonal changes, if any',
						hint: 'For example: closed in January, or longer hours from June to August.',
						kind: 'longtext',
						required: false,
						maxLength: 500
					}
				]
			}
		]
	}
];

export const SETUP_FACTS = new Map<string, SetupFact>(
	SETUP_SECTIONS.flatMap((section) =>
		section.groups.flatMap((group) => group.facts.map((fact) => [fact.key, fact] as const))
	)
);

export function setupSection(key: string): SetupSection | undefined {
	return SETUP_SECTIONS.find((section) => section.key === key);
}

/**
 * What a support chat asked from a setup section (D6) is about, in words. A section since removed from the
 * task list still reads as setup rather than as nothing.
 */
export function setupSectionLabel(key: string | null): string | null {
	if (!key) return null;
	return setupSection(key)?.title ?? 'Setup';
}

export function sectionFacts(section: SetupSection): SetupFact[] {
	return section.groups.flatMap((group) => group.facts);
}

export type SetupAnswer = {
	availability: SetupAvailability;
	value: string | null;
	note: string | null;
};

export type SetupAnswers = Record<string, SetupAnswer | undefined>;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
// Loose on purpose: the country is not known until a later section, so this only rules out text that
// cannot be a phone number at all. Seven digits is the shortest real subscriber number.
const PHONE_PATTERN = /^\+?[0-9 ().-]{7,24}$/;

function isTimeZone(value: string): boolean {
	if (value.length > 80) return false;
	try {
		new Intl.DateTimeFormat('en-US', { timeZone: value });
		return true;
	} catch {
		return false;
	}
}

/**
 * What the database keeps for an answer that has already passed `setupValueError`. Most answers are the
 * text itself; hours and dated exceptions are kept as real JSON so nothing downstream has to parse text.
 */
export function storedSetupValue(fact: SetupFact, value: string): unknown {
	if (fact.kind === 'hours') return parseSetupHours(value).value;
	if (fact.kind === 'hours_exceptions') return parseSetupHoursExceptions(value).value;
	return value;
}

/** Why a typed value cannot be saved, in words for the person typing it — or null when it can. */
export function setupValueError(fact: SetupFact, raw: string): string | null {
	const value = raw.trim();
	if (!value) return null;
	switch (fact.kind) {
		case 'email':
			if (value.length > 254 || !EMAIL_PATTERN.test(value))
				return 'Enter an email address like name@example.com.';
			return null;
		case 'phone':
			if (!PHONE_PATTERN.test(value) || value.replace(/\D/g, '').length < 7)
				return 'Enter a phone number with at least 7 digits.';
			return null;
		case 'choice':
			return fact.options?.some((option) => option.value === value) ? null : 'Choose an option.';
		case 'country':
			return /^[A-Z]{2}$/.test(value) ? null : 'Choose a country from the list.';
		case 'timezone':
			return isTimeZone(value) ? null : 'Choose a time zone from the list.';
		case 'hours':
			return parseSetupHours(value).error;
		case 'hours_exceptions':
			return parseSetupHoursExceptions(value).error;
		default:
			if (fact.maxLength && value.length > fact.maxLength)
				return `Keep this under ${fact.maxLength} characters.`;
			return null;
	}
}

export type SetupSectionStatus = 'not_started' | 'in_progress' | 'done';

/** Required facts that still have no answer of any kind. "Not yet" and "need help" are answers. */
export function missingRequiredFacts(section: SetupSection, answers: SetupAnswers): SetupFact[] {
	return sectionFacts(section).filter((fact) => fact.required && !answers[fact.key]);
}

// Done is the administrator's own word for it (GOV.UK task list), but it only holds while every required
// fact still has an answer — clearing one reopens the section without anyone having to un-tick it.
export function sectionStatus(
	section: SetupSection,
	answers: SetupAnswers,
	markedDone: boolean
): SetupSectionStatus {
	if (markedDone && missingRequiredFacts(section, answers).length === 0) return 'done';
	const anyAnswer = sectionFacts(section).some((fact) => answers[fact.key]);
	return anyAnswer || markedDone ? 'in_progress' : 'not_started';
}
