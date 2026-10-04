// What the client setup wizard asks, and the rules every answer is checked against. The stages, headings and
// questions themselves are a published version in the database that Jafar edits
// (docs/adr/0006-setup-questions-live-in-published-versions.md); this module turns that version into the
// sections the page, the server's validation and the task list's progress all read, so they can never
// disagree about what a section contains. A fact is asked once and stored under its key (ADR 0005).

import { COMMON_CURRENCIES } from '$lib/settings/currencies';
import { TRADES } from '$lib/settings/trades';
import {
	OTHER_MAX_LENGTH,
	SETUP_DISTANCE_UNITS,
	SETUP_DURATION_UNITS,
	parseSetupChoices,
	parseSetupColours,
	parseSetupMeasure,
	parseSetupMoney,
	parseSetupNumber,
	parseSetupPercentage,
	parseSetupUrl,
	setupChoiceList
} from '$lib/setup/answer-values';
import { parseSetupFileIds, type SetupFileKind } from '$lib/setup/files';
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
	| 'date'
	// The kinds below are saved as described in `$lib/setup/answer-values`.
	/** Tick several. */
	| 'multi_choice'
	/** A web address. */
	| 'url'
	| 'number'
	| 'money'
	| 'percentage'
	| 'distance'
	/** A length of time. */
	| 'duration'
	/** Brand colours as codes like #1A73E8. */
	| 'colours'
	/** Photos or files: the File Manager ids, as described in `$lib/setup/files`. */
	| 'file';

/** The answer types Jafar can give a question that is not built in (plan §2.1). */
export const SETUP_QUESTION_KINDS = [
	'text',
	'longtext',
	'choice',
	'multi_choice',
	'yes_no',
	'yes_no_unsure',
	'phone',
	'email',
	'date',
	'url',
	'number',
	'money',
	'percentage',
	'distance',
	'duration',
	'colours',
	'file'
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
	/** `multi_choice`: also offers "Other" with a box for the client's own words. */
	allowOther?: boolean;
	/** `multi_choice`: the most choices a client may tick. */
	maxChoices?: number;
	/** `file`: the kinds of file accepted. */
	fileKinds?: SetupFileKind[];
	/** `file`: the most files one answer may hold. */
	maxFiles?: number;
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
	/** Asked only when every condition holds (plan §2.1 "show only if"). */
	showIf?: SetupCondition[];
};

/**
 * One "show only if" condition: an earlier answer is one of `values`, or the client's package includes a
 * service. A client's own catalogue has no service conditions left — see {@link catalogueForServices}.
 */
export type SetupCondition = { factKey: string; values: string[] } | { serviceKey: string };

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
	allow_other?: boolean;
	max_choices?: number | null;
	file_kinds?: SetupFileKind[] | null;
	max_files?: number | null;
	max_length: number | null;
	show_if?: ({ fact_key: string; values: string[] } | { service_key: string })[] | null;
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
	if (item.kind === 'yes_no_unsure')
		return {
			kind: 'choice',
			layout: 'radio',
			options: [...YES_NO('Yes', 'No'), { value: 'not_sure', label: 'Not sure' }]
		};
	// A pick-one question with "Other" works as the built-in trade question does: the client's own words are
	// saved in place of a choice.
	if (item.kind === 'choice' && item.allow_other)
		return {
			kind: 'choice_other',
			// The page shows the box for the client's words while this last choice is picked.
			options: [...(item.options ?? []), { value: 'Other', label: 'Other' }],
			otherLabel: 'Tell us which',
			maxLength: OTHER_MAX_LENGTH
		};
	if (item.kind === 'multi_choice')
		return {
			kind: 'multi_choice',
			options: item.options ?? [],
			...(item.allow_other ? { allowOther: true } : {}),
			...(item.max_choices ? { maxChoices: item.max_choices } : {})
		};
	if (item.kind === 'file')
		return { kind: 'file', fileKinds: item.file_kinds ?? ['photo'], maxFiles: item.max_files ?? 1 };
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
				builtIn: item.built_in,
				...(item.show_if?.length ? { showIf: item.show_if.map(condition) } : {})
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

function condition(row: NonNullable<CatalogueItemRow['show_if']>[number]): SetupCondition {
	return 'service_key' in row
		? { serviceKey: row.service_key }
		: { factKey: row.fact_key, values: row.values };
}

/**
 * The stages one client is asked: those shown to everyone, and those whose service the client's package
 * includes (plan §2.1). A question that asks for a service the package lacks is left out too, and the
 * service conditions of the rest are settled, so only conditions on earlier answers remain. Everything a
 * client reads or saves goes through this.
 */
export function catalogueForServices(
	catalogue: SetupCatalogue,
	serviceKeys: ReadonlySet<string>
): SetupCatalogue {
	const included = (condition: SetupCondition) =>
		!('serviceKey' in condition) || serviceKeys.has(condition.serviceKey);
	return {
		...catalogue,
		sections: catalogue.sections
			.filter((section) => section.serviceKey === null || serviceKeys.has(section.serviceKey))
			.map((section) => ({
				...section,
				groups: section.groups
					.map((group) => ({
						...group,
						facts: group.facts
							.filter((fact) => !fact.showIf || fact.showIf.every(included))
							.map((fact) => {
								if (!fact.showIf) return fact;
								const settled: SetupFact = {
									...fact,
									showIf: fact.showIf.filter((condition) => 'factKey' in condition)
								};
								if (!settled.showIf?.length) delete settled.showIf;
								return settled;
							})
					}))
					.filter((group) => group.facts.length > 0)
			}))
			.filter((section) => section.groups.length > 0)
	};
}

/** Whether an answer is one of the values a condition names. A tick-several answer matches when any tick does. */
function answerMatches(answer: SetupAnswer | undefined, values: readonly string[]): boolean {
	if (answer?.availability !== 'have' || answer.value === null) return false;
	const list = setupChoiceList(answer.value);
	return list ? list.some((value) => values.includes(value)) : values.includes(answer.value);
}

/**
 * The questions a client is asked, given their answers so far: walks `facts` in setup order, so a question
 * whose earlier question is hidden is hidden too. "I don't have this yet" and "I need Uplift's help" match
 * no condition. `shownBefore` names questions outside `facts` already known to be asked, whose answers are
 * in `answers` — how one section's page judges conditions on an earlier section.
 */
export function shownFacts(
	facts: readonly SetupFact[],
	answers: SetupAnswers,
	shownBefore: ReadonlySet<string> = new Set()
): Set<string> {
	const shown = new Set(shownBefore);
	for (const fact of facts) {
		const asked = (fact.showIf ?? []).every(
			(condition) =>
				'factKey' in condition &&
				shown.has(condition.factKey) &&
				answerMatches(answers[condition.factKey], condition.values)
		);
		if (asked) shown.add(fact.key);
	}
	return shown;
}

/** Every question across the catalogue this client is asked now. */
export function shownCatalogueFacts(catalogue: SetupCatalogue, answers: SetupAnswers): Set<string> {
	return shownFacts(catalogue.sections.flatMap(sectionFacts), answers);
}

/**
 * The earlier-section questions a section's conditions depend on that are asked now, with their answers —
 * what the section's page needs to show and hide its questions as the client types.
 */
export function earlierAnswersFor(
	section: SetupSection,
	catalogue: SetupCatalogue,
	answers: SetupAnswers
): SetupAnswers {
	const own = new Set(sectionFacts(section).map((fact) => fact.key));
	const shown = shownCatalogueFacts(catalogue, answers);
	const earlier: SetupAnswers = {};
	for (const fact of sectionFacts(section))
		for (const condition of fact.showIf ?? [])
			if ('factKey' in condition && !own.has(condition.factKey) && shown.has(condition.factKey))
				earlier[condition.factKey] = answers[condition.factKey];
	return earlier;
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
	return parsedValue(fact, value)?.value ?? value;
}

/** The A5c and A5d kinds' own parse of a value, or undefined for a kind checked another way. */
function parsedValue(fact: SetupFact, value: string) {
	switch (fact.kind) {
		case 'multi_choice':
			return parseSetupChoices(value, {
				options: fact.options ?? [],
				allowOther: fact.allowOther ?? false,
				maxChoices: fact.maxChoices
			});
		case 'url':
			return parseSetupUrl(value);
		case 'number':
			return parseSetupNumber(value);
		case 'percentage':
			return parseSetupPercentage(value);
		case 'money':
			return parseSetupMoney(value);
		case 'distance':
			return parseSetupMeasure(value, SETUP_DISTANCE_UNITS, 'distance');
		case 'duration':
			return parseSetupMeasure(value, SETUP_DURATION_UNITS, 'time');
		case 'colours':
			return parseSetupColours(value);
		case 'file':
			return parseSetupFileIds(value, fact.maxFiles ?? 1);
		default:
			return undefined;
	}
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
		case 'multi_choice':
		case 'url':
		case 'number':
		case 'percentage':
		case 'money':
		case 'distance':
		case 'duration':
		case 'colours':
		case 'file':
			return parsedValue(fact, value)?.error ?? null;
		default:
			if (fact.maxLength && value.length > fact.maxLength)
				return `Keep this under ${fact.maxLength} characters.`;
			return null;
	}
}

export type SetupSectionStatus = 'not_started' | 'in_progress' | 'done';

/**
 * Required facts that are asked and still have no answer of any kind. "Not yet" and "need help" are
 * answers; a hidden question is never required.
 */
export function missingRequiredFacts(
	section: SetupSection,
	answers: SetupAnswers,
	shown: ReadonlySet<string>
): SetupFact[] {
	return sectionFacts(section).filter(
		(fact) => fact.required && shown.has(fact.key) && !answers[fact.key]
	);
}

// Done is the administrator's own word for it (GOV.UK task list), but it only holds while every required
// fact still has an answer — clearing one reopens the section without anyone having to un-tick it.
export function sectionStatus(
	section: SetupSection,
	answers: SetupAnswers,
	markedDone: boolean,
	shown: ReadonlySet<string>
): SetupSectionStatus {
	if (markedDone && missingRequiredFacts(section, answers, shown).length === 0) return 'done';
	const anyAnswer = sectionFacts(section).some((fact) => shown.has(fact.key) && answers[fact.key]);
	return anyAnswer || markedDone ? 'in_progress' : 'not_started';
}
