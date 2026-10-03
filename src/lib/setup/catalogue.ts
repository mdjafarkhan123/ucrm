// What the client setup wizard asks, and the rules every answer is checked against. The stages, headings and
// questions themselves are a published version in the database that Jafar edits
// (docs/adr/0006-setup-questions-live-in-published-versions.md); this module turns that version into the
// sections the page, the server's validation and the task list's progress all read, so they can never
// disagree about what a section contains. A fact is asked once and stored under its key (ADR 0005).

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
	| 'hours_exceptions'
	/** A calendar day, saved as YYYY-MM-DD. */
	| 'date';

/** The answer types Jafar can give a question that is not built in (plan §2.1). */
export const SETUP_QUESTION_KINDS = [
	'text',
	'longtext',
	'choice',
	'yes_no',
	'phone',
	'email',
	'date'
] as const;
export type SetupQuestionKind = (typeof SETUP_QUESTION_KINDS)[number];

/** What a question's answer may be. A built-in question takes these from `BUILT_IN_FACTS`, never the database. */
type SetupFactRules = {
	kind: SetupFactKind;
	maxLength?: number;
	options?: { value: string; label: string }[];
	/** Shows a short list of choices as radio buttons instead of a dropdown. */
	layout?: 'radio';
	/** `choice_other`: the label of the box that appears when "Other" is picked. */
	otherLabel?: string;
};

export type SetupFact = SetupFactRules & {
	key: string;
	label: string;
	hint?: string;
	required: boolean;
	/** Offers "I don't have this yet" and "I need Uplift's help" beside the answer. */
	canDefer?: boolean;
	/** The app copies this answer into CRM settings or provider registration, so it can never be deleted. */
	builtIn: boolean;
};

export type SetupGroup = { title: string; hint: string; facts: SetupFact[] };

export type SetupSection = {
	key: string;
	title: string;
	description: string;
	/** Shown only to clients whose package includes this service; null shows it to everyone. */
	serviceKey: string | null;
	groups: SetupGroup[];
};

export type SetupCatalogue = { versionId: string; sections: SetupSection[] };

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

// Answers the app itself reads — copied into CRM settings or provider registration, or used to suggest an
// answer from the account. Jafar may reword and move these questions, never delete them or change what
// their answer is, so their rules live here rather than in the version he edits.
export const BUILT_IN_FACTS: Record<string, SetupFactRules> = {
	'business.public_name': { kind: 'text', maxLength: 120 },
	'business.legal_name': { kind: 'text', maxLength: 160 },
	'business.trade': {
		kind: 'choice_other',
		maxLength: 120,
		options: TRADES.map((trade) => ({ value: trade, label: trade })),
		otherLabel: 'Your trade'
	},
	'business.type': {
		kind: 'choice',
		options: [
			{ value: 'sole_trader', label: 'Sole trader / self-employed' },
			{ value: 'partnership', label: 'Partnership' },
			{ value: 'company', label: 'Limited company, LLC or corporation' },
			{ value: 'other', label: 'Something else' },
			{ value: 'unsure', label: "I'm not sure" }
		]
	},
	'business.contact_name': { kind: 'text', maxLength: 120 },
	'business.contact_email': { kind: 'email' },
	'business.contact_phone': { kind: 'phone' },
	'business.approver_name': { kind: 'text', maxLength: 120 },
	'business.approver_email': { kind: 'email' },
	'business.public_phone': { kind: 'phone' },
	'business.public_email': { kind: 'email' },
	'business.country': { kind: 'country' },
	'business.address_line1': { kind: 'text', maxLength: 160 },
	'business.address_line2': { kind: 'text', maxLength: 160 },
	'business.address_city': { kind: 'text', maxLength: 120 },
	'business.address_region': { kind: 'text', maxLength: 120 },
	'business.address_postal_code': { kind: 'text', maxLength: 20 },
	'business.address_customers_visit': {
		kind: 'choice',
		layout: 'radio',
		options: YES_NO('Yes, customers visit', 'No, I go to them')
	},
	'business.address_public': {
		kind: 'choice',
		layout: 'radio',
		options: YES_NO('Yes, show the full address', 'No, keep it private')
	},
	'business.language': {
		kind: 'choice_other',
		maxLength: 60,
		options: LANGUAGES.map((language) => ({ value: language, label: language })),
		otherLabel: 'Your language'
	},
	'business.timezone': { kind: 'timezone' },
	'business.currency': {
		kind: 'choice',
		options: COMMON_CURRENCIES.map((currency) => ({
			value: currency.code,
			label: `${currency.code} — ${currency.label}`
		}))
	},
	'business.hours': { kind: 'hours' },
	'business.hours_exceptions': { kind: 'hours_exceptions' }
};

/** One item of `public.setup_published_catalogue()`. */
type CatalogueItemRow = {
	type: 'heading' | 'question';
	fact_key: string | null;
	label: string;
	hint: string | null;
	built_in: boolean;
	required: boolean;
	can_defer: boolean;
	kind: SetupQuestionKind | null;
	options: { value: string; label: string }[] | null;
	max_length: number | null;
};

export type SetupCatalogueRow = {
	version_id: string;
	stages: {
		key: string;
		title: string;
		description: string;
		service_key: string | null;
		items: CatalogueItemRow[];
	}[];
};

function factRules(item: CatalogueItemRow): SetupFactRules | null {
	if (item.built_in) return item.fact_key ? (BUILT_IN_FACTS[item.fact_key] ?? null) : null;
	if (!item.kind) return null;
	// Yes/no is a two-choice question shown as radio buttons, saved as "yes" or "no".
	if (item.kind === 'yes_no')
		return { kind: 'choice', layout: 'radio', options: YES_NO('Yes', 'No') };
	return {
		kind: item.kind,
		...(item.max_length ? { maxLength: item.max_length } : {}),
		...(item.options ? { options: item.options } : {})
	};
}

/**
 * The published version as sections of grouped questions, for every client. A heading starts a group;
 * questions before the first heading form an untitled one. A built-in question this code does not know is left out rather than
 * asked with no rules — it can only appear if the database is ahead of the app.
 */
export function buildSetupCatalogue(row: SetupCatalogueRow): SetupCatalogue {
	const sections = row.stages.map((stage): SetupSection => {
		const groups: SetupGroup[] = [];
		for (const item of stage.items) {
			if (item.type === 'heading') {
				groups.push({ title: item.label, hint: item.hint ?? '', facts: [] });
				continue;
			}
			const rules = factRules(item);
			if (!item.fact_key || !rules) {
				console.error(
					`Setup question ${item.fact_key ?? '(no key)'} has no answer rules; skipped.`
				);
				continue;
			}
			if (groups.length === 0) groups.push({ title: '', hint: '', facts: [] });
			groups[groups.length - 1].facts.push({
				...rules,
				key: item.fact_key,
				label: item.label,
				...(item.hint ? { hint: item.hint } : {}),
				required: item.required,
				...(item.can_defer ? { canDefer: true } : {}),
				builtIn: item.built_in
			});
		}
		return {
			key: stage.key,
			title: stage.title,
			description: stage.description,
			serviceKey: stage.service_key,
			groups: groups.filter((group) => group.facts.length > 0)
		};
	});
	// A stage Jafar has added but not yet given a question asks nothing, so no client sees it.
	return {
		versionId: row.version_id,
		sections: sections.filter((section) => section.groups.length > 0)
	};
}

/**
 * The stages one client is asked: those shown to everyone, and those whose service the client's package
 * includes (plan §2.1). Everything a client reads or saves goes through this.
 */
export function catalogueForServices(
	catalogue: SetupCatalogue,
	serviceKeys: ReadonlySet<string>
): SetupCatalogue {
	return {
		...catalogue,
		sections: catalogue.sections.filter(
			(section) => section.serviceKey === null || serviceKeys.has(section.serviceKey)
		)
	};
}

export function catalogueFacts(catalogue: SetupCatalogue): Map<string, SetupFact> {
	return new Map(
		catalogue.sections.flatMap((section) =>
			sectionFacts(section).map((fact) => [fact.key, fact] as const)
		)
	);
}

export function catalogueSection(catalogue: SetupCatalogue, key: string): SetupSection | undefined {
	return catalogue.sections.find((section) => section.key === key);
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

function isCalendarDate(value: string): boolean {
	if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
	const date = new Date(`${value}T00:00:00Z`);
	return !Number.isNaN(date.getTime()) && date.toISOString().startsWith(value);
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
		case 'date':
			return isCalendarDate(value) ? null : 'Choose a date from the calendar.';
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
