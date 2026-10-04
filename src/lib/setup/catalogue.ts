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
import { PROTECTED_FILE_KINDS, parseSetupFileIds, type SetupFileKind } from '$lib/setup/files';
import { parseSetupHours, parseSetupHoursExceptions } from '$lib/setup/hours';
import { parseSetupList, setupListRows, type SetupListField } from '$lib/setup/lists';
import { keptSetupPickIds, parseSetupPick, setupPickIds, setupPickMinimum } from '$lib/setup/picks';
import { setupReuseSource } from '$lib/setup/reuse';

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
	| 'file'
	/**
	 * B9a: sensitive provider documents, such as a phone bill. Saved like `file`, but the ids are protected
	 * documents (`$lib/server/setup/protected-documents`), which only the owner and Jafar can open.
	 */
	| 'protected_file'
	/** Add-another rows of named boxes, as described in `$lib/setup/lists`. */
	| 'list'
	/** Rows picked from an earlier list, as described in `$lib/setup/picks`. */
	| 'pick';

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
	'file',
	'list',
	'pick',
	'reuse'
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
	/** `multi_choice` and `pick`: the most choices a client may tick. */
	maxChoices?: number;
	/** `pick`: the earlier list question whose rows the client picks from. */
	pickFrom?: string;
	/** `pick`: the fewest rows to pick, or every row when the list holds fewer. */
	minChoices?: number;
	/** `pick`: the client puts the picked rows in order, most important first. */
	ordered?: boolean;
	/** `pick`: the box of the list's rows that names each one — its first. Filled in from the list. */
	pickNameKey?: string;
	/** `pick`: the list question's own wording, for "Add some to … first". Filled in from the list. */
	pickListLabel?: string;
	/** `file`: the kinds of file accepted. */
	fileKinds?: SetupFileKind[];
	/** `file`: the most files one answer may hold. */
	maxFiles?: number;
	/** `list`: the boxes each row holds. */
	listFields?: SetupListField[];
	/** `list`: the most rows; 1 is a plain form. */
	maxRows?: number;
	/**
	 * A5g: the earlier question whose answer this one shows to confirm. Its answer rules are that question's,
	 * for an answer different from it. Left off for a client who is not asked that question.
	 */
	reuseFrom?: string;
	/** A5g: the earlier question's wording and section, for "You told us in …" and its Change link. */
	reuseLabel?: string;
	reuseSection?: { key: string; title: string };
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
 * service. A client's own catalogue has no service conditions left — see {@link catalogueForServices}. A pick
 * question also carries `hasRows` on its list (A5f): it is asked only once that list holds a row.
 */
export type SetupCondition =
	| { factKey: string; values: string[] }
	| { factKey: string; hasRows: true }
	| { serviceKey: string };

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
	// Whether the legal name below applies: a texting registration needs the one the business is registered under.
	'business.legal_name_differs': {
		kind: 'choice',
		layout: 'radio',
		options: YES_NO('Yes, it is different', 'No, it is the same')
	},
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
			{ value: 'sole_trader', label: 'Sole trader / sole proprietor' },
			{ value: 'partnership', label: 'Partnership' },
			{ value: 'company', label: 'Limited company, LLC or corporation' },
			{ value: 'nonprofit', label: 'Nonprofit or charity' },
			{ value: 'other', label: 'Something else' },
			{ value: 'unsure', label: "I'm not sure" }
		]
	},
	'business.contact_name': { kind: 'text', maxLength: 120 },
	'business.contact_email': { kind: 'email' },
	'business.contact_phone': { kind: 'phone' },
	// Who confirms the finished system before launch (B13): this person, or the approver named next.
	'business.contact_is_approver': {
		kind: 'choice',
		layout: 'radio',
		options: YES_NO('Yes', 'No, someone else does')
	},
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
	// How the hours below are read: no weekly hours is not "closed" for a business open around the clock.
	'business.availability': {
		kind: 'choice',
		layout: 'radio',
		options: [
			{ value: 'set_hours', label: 'At set opening hours' },
			{ value: 'always', label: '24 hours a day, 7 days a week' },
			{ value: 'appointment_only', label: 'By appointment only' }
		]
	},
	'business.hours': { kind: 'hours' },
	'business.hours_exceptions': { kind: 'hours_exceptions' }
};

/** One box of a list question, as the database keeps it. */
type ListFieldRow = Omit<SetupListField, 'fileKinds'> & { file_kinds?: SetupFileKind[] };

/** One item of `public.setup_published_catalogue()`. */
type CatalogueItemRow = {
	type: 'heading' | 'question';
	fact_key: string | null;
	label: string;
	hint: string | null;
	built_in: boolean;
	required: boolean;
	can_defer: boolean;
	// B9b adds 'protected_file' to the editor's kinds; until then only starter content can use it.
	kind: SetupQuestionKind | 'protected_file' | null;
	options: { value: string; label: string }[] | null;
	allow_other?: boolean;
	max_choices?: number | null;
	file_kinds?: SetupFileKind[] | null;
	max_files?: number | null;
	list_fields?: ListFieldRow[] | null;
	max_rows?: number | null;
	pick_from?: string | null;
	min_choices?: number | null;
	ordered?: boolean;
	reuse_from?: string | null;
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
	if (item.kind === 'protected_file')
		return {
			kind: 'protected_file',
			fileKinds: PROTECTED_FILE_KINDS,
			maxFiles: item.max_files ?? 1
		};
	if (item.kind === 'list')
		return {
			kind: 'list',
			listFields: (item.list_fields ?? []).map(({ file_kinds, ...field }) => ({
				...field,
				...(file_kinds ? { fileKinds: file_kinds } : {})
			})),
			maxRows: item.max_rows ?? 1
		};
	if (item.kind === 'pick')
		return item.pick_from
			? {
					kind: 'pick',
					pickFrom: item.pick_from,
					...(item.min_choices ? { minChoices: item.min_choices } : {}),
					...(item.max_choices ? { maxChoices: item.max_choices } : {}),
					...(item.ordered ? { ordered: true } : {})
				}
			: null;
	// A5g: the earlier question's rules replace these once the whole version is read — see linkReuses.
	if (item.kind === 'reuse')
		return item.reuse_from ? { kind: 'text', reuseFrom: item.reuse_from } : null;
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
	linkPicks(sections);
	linkReuses(sections);
	// A stage Jafar has added but not yet given a question asks nothing, so no client sees it.
	return {
		versionId: row.version_id,
		sections: sections.filter((section) => section.groups.length > 0)
	};
}

/**
 * Gives each pick what it needs from its list: the box that names a row, the list's wording, and the rule
 * that it is asked only once the list holds a row. A pick whose list this version no longer has is left out;
 * the database refuses to publish one, so it can only happen if the database is ahead of the app.
 */
function linkPicks(sections: SetupSection[]) {
	const lists = new Map(
		sections.flatMap((section) =>
			sectionFacts(section).flatMap((fact) =>
				fact.kind === 'list' ? [[fact.key, fact] as const] : []
			)
		)
	);
	for (const section of sections)
		for (const group of section.groups)
			group.facts = group.facts.flatMap((fact) => {
				if (fact.kind !== 'pick') return [fact];
				const list = fact.pickFrom ? lists.get(fact.pickFrom) : undefined;
				if (!list) {
					console.error(`Setup question ${fact.key} picks from a list that is not asked; skipped.`);
					return [];
				}
				return [
					{
						...fact,
						pickNameKey: list.listFields?.[0]?.key,
						pickListLabel: list.label,
						showIf: [{ factKey: list.key, hasRows: true as const }, ...(fact.showIf ?? [])]
					}
				];
			});
}

/**
 * Gives each reuse its earlier question's answer rules, wording and section. A reuse whose question this version
 * no longer has, or whose answer cannot be shown back, is left out; the database refuses to publish one, so it
 * can only happen if the database is ahead of the app.
 */
function linkReuses(sections: SetupSection[]) {
	const sources = new Map(
		sections.flatMap((section) =>
			sectionFacts(section).map((fact) => [fact.key, { fact, section }] as const)
		)
	);
	for (const section of sections)
		for (const group of section.groups)
			group.facts = group.facts.flatMap((fact) => {
				if (!fact.reuseFrom) return [fact];
				const source = sources.get(fact.reuseFrom);
				if (
					!source ||
					source.fact.reuseFrom ||
					['file', 'protected_file', 'pick'].includes(source.fact.kind)
				) {
					console.error(`Setup question ${fact.key} reuses a question it cannot; skipped.`);
					return [];
				}
				const { key, label, hint, required, canDefer, builtIn, showIf, ...rules } = source.fact;
				return [
					{
						...rules,
						key: fact.key,
						label: fact.label,
						...(fact.hint ? { hint: fact.hint } : {}),
						required: fact.required,
						...(fact.canDefer ? { canDefer: true } : {}),
						builtIn: false,
						...(fact.showIf ? { showIf: fact.showIf } : {}),
						reuseFrom: source.fact.key,
						reuseLabel: source.fact.label,
						reuseSection: { key: source.section.key, title: source.section.title }
					}
				];
			});
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
	const client = {
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
	// A5g: a reuse of a question this client is not asked is asked afresh, as a question of that type.
	const asked = catalogueFacts(client);
	for (const section of client.sections)
		for (const group of section.groups)
			group.facts = group.facts.map((fact) => {
				if (!fact.reuseFrom || asked.has(fact.reuseFrom)) return fact;
				const { reuseFrom, reuseLabel, reuseSection, ...plain } = fact;
				return plain;
			});
	return client;
}

/**
 * Whether an answer meets a condition: it is one of the values the condition names — a tick-several answer
 * when any tick is — or, for a pick's list, it holds at least one row.
 */
function answerMatches(
	answer: SetupAnswer | undefined,
	condition: { values: readonly string[] } | { hasRows: true }
): boolean {
	if (answer?.availability !== 'have' || answer.value === null) return false;
	if ('hasRows' in condition) return setupListRows(answer.value).length > 0;
	const list = setupChoiceList(answer.value);
	return list
		? list.some((value) => condition.values.includes(value))
		: condition.values.includes(answer.value);
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
				answerMatches(answers[condition.factKey], condition)
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
	for (const fact of sectionFacts(section)) {
		for (const condition of fact.showIf ?? [])
			if ('factKey' in condition && !own.has(condition.factKey) && shown.has(condition.factKey))
				earlier[condition.factKey] = answers[condition.factKey];
		// A5g: the earlier answer a reuse shows to confirm.
		if (fact.reuseFrom && !own.has(fact.reuseFrom) && shown.has(fact.reuseFrom))
			earlier[fact.reuseFrom] = answers[fact.reuseFrom];
	}
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
	const same = fact.reuseFrom ? setupReuseSource(value) : null;
	if (same) return { same_as: same };
	if (fact.kind === 'hours') return parseSetupHours(value).value;
	if (fact.kind === 'hours_exceptions') return parseSetupHoursExceptions(value).value;
	if (fact.kind === 'pick') return setupPickIds(value);
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
		case 'protected_file':
			return parseSetupFileIds(value, fact.maxFiles ?? 1);
		case 'list':
			return parseSetupList(
				value,
				{ fields: fact.listFields ?? [], maxRows: fact.maxRows ?? 1 },
				listCellValue
			);
		default:
			return undefined;
	}
}

/**
 * One box of a list question as a question of its own, so the page shows it and this module checks it exactly
 * as a question of that type. `key` names it on the page; a file box holds one file.
 */
export function setupListFieldFact(field: SetupListField, key = field.key): SetupFact {
	const base = { key, label: field.label, required: field.required, builtIn: false };
	switch (field.kind) {
		case 'yes_no':
			return { ...base, kind: 'choice', layout: 'radio', options: YES_NO('Yes', 'No') };
		case 'choice':
			return { ...base, kind: 'choice', options: field.options ?? [] };
		case 'file':
			return { ...base, kind: 'file', fileKinds: field.fileKinds ?? ['photo'], maxFiles: 1 };
		case 'text':
			return { ...base, kind: 'text', maxLength: 200 };
		case 'longtext':
			return { ...base, kind: 'longtext', maxLength: 2000 };
		default:
			return { ...base, kind: field.kind };
	}
}

/** A list box's value, checked exactly as a question of its type is. A file box's value is the one id. */
function listCellValue(field: SetupListField, text: string) {
	if (field.kind === 'file') {
		const ids = parseSetupFileIds(JSON.stringify([text]), 1);
		return ids.error === null ? { value: ids.value[0], error: null } : ids;
	}
	const fact = setupListFieldFact(field);
	const error = setupValueError(fact, text);
	return error === null
		? { value: storedSetupValue(fact, text), error: null }
		: { value: null, error };
}

/**
 * Why a typed value cannot be saved, in words for the person typing it — or null when it can. A pick is
 * checked against its list's answer in `answers`.
 */
export function setupValueError(
	fact: SetupFact,
	raw: string,
	answers: SetupAnswers = {}
): string | null {
	const value = raw.trim();
	if (!value) return null;
	// A5g: "Yes, use this" holds only while the earlier answer it means is given.
	const same = setupReuseSource(value);
	if (same !== null) {
		if (same !== fact.reuseFrom)
			return 'This answer could not be read. Reload the page and try again.';
		return answers[same]?.availability === 'have'
			? null
			: `Answer “${fact.reuseLabel}” first, or use a different one here.`;
	}
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
		case 'protected_file':
		case 'list':
			return parsedValue(fact, value)?.error ?? null;
		case 'pick':
			return parseSetupPick(value, setupListRows(answers[fact.pickFrom ?? '']?.value), fact).error;
		default:
			if (fact.maxLength && value.length > fact.maxLength)
				return `Keep this under ${fact.maxLength} characters.`;
			return null;
	}
}

export type SetupSectionStatus = 'not_started' | 'in_progress' | 'done';

/**
 * What a saved answer still lacks before its section can be marked done, in words — or null. Only a pick has
 * this: it saves as the client ticks, but needs Jafar's fewest picks, or every row when the list holds fewer.
 */
export function setupAnswerShortfall(fact: SetupFact, answers: SetupAnswers): string | null {
	const answer = answers[fact.key];
	if (fact.kind !== 'pick' || answer?.availability !== 'have') return null;
	const rows = setupListRows(answers[fact.pickFrom ?? '']?.value);
	const picked = keptSetupPickIds(setupPickIds(answer.value), rows).length;
	const least = setupPickMinimum(fact, rows.length);
	return picked < least ? `Pick at least ${least}.` : null;
}

/**
 * Whether a question has an answer of any kind. A5g: "Yes, use this" counts only while the earlier answer it
 * means is given — and is asked of this client.
 */
export function setupAnswerGiven(fact: SetupFact, answers: SetupAnswers): boolean {
	const answer = answers[fact.key];
	if (!answer) return false;
	const same = answer.availability === 'have' ? setupReuseSource(answer.value) : null;
	return same === null || (same === fact.reuseFrom && answers[same]?.availability === 'have');
}

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
		(fact) => fact.required && shown.has(fact.key) && !setupAnswerGiven(fact, answers)
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
	const anyAnswer = sectionFacts(section).some(
		(fact) => shown.has(fact.key) && setupAnswerGiven(fact, answers)
	);
	return anyAnswer || markedDone ? 'in_progress' : 'not_started';
}
