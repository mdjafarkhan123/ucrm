// Every question the client setup wizard asks, in one place. A fact is asked once and stored under its
// key (docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md), so the page, the server's
// validation and the task list's progress all read this same list and can never disagree about what a
// section contains. Adding a question is a new entry here, not a database change.

import { TRADES } from '$lib/settings/trades';

export type SetupAvailability = 'have' | 'not_yet' | 'need_help';

export type SetupFactKind = 'text' | 'email' | 'phone' | 'choice' | 'trade';

export type SetupFact = {
	key: string;
	label: string;
	hint?: string;
	kind: SetupFactKind;
	required: boolean;
	maxLength?: number;
	options?: { value: string; label: string }[];
	/** Offers "I don't have this yet" and "I need Uplift's help" beside the answer. */
	canDefer?: boolean;
};

export type SetupGroup = { title: string; hint: string; facts: SetupFact[] };

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
						kind: 'trade',
						required: true,
						maxLength: 120,
						options: TRADES.map((trade) => ({ value: trade, label: trade }))
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
