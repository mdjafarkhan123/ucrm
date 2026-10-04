// Client onboarding A4 and A5 (plan §2.1, ADR 0006): Jafar's setup editor. Stages and their questions are
// edited as a draft and published; clients see only the published version, each limited to the stages their
// package includes.

import { BUILT_IN_FACTS, type SetupQuestionKind } from '$lib/setup/catalogue';
import type { SetupFileKind } from '$lib/setup/files';
import {
	SETUP_LIST_STARTERS,
	type SetupListField,
	type SetupListFieldKind
} from '$lib/setup/lists';

export type SetupChoice = { value: string; label: string };

export type SetupEditorItem = {
	type: 'heading' | 'question';
	fact_key: string | null;
	label: string;
	hint: string | null;
	built_in: boolean;
	required: boolean;
	can_defer: boolean;
	/** Null for a heading or a built-in question, whose answer type lives in code. */
	kind: SetupQuestionKind | null;
	options: SetupChoice[] | null;
	/** Pick one and tick several: also offer "Other" with a box for the client's own words. */
	allow_other: boolean;
	/** Tick several: the most ticks a client may give; null allows any number. */
	max_choices: number | null;
	/** Photo or file: the kinds of file it accepts. Null for every other type. */
	file_kinds: SetupFileKind[] | null;
	/** Photo or file: how many files a client may add. Null for every other type. */
	max_files: number | null;
	/** Add-another list: the boxes each row holds, as the database keeps them. Null for every other type. */
	list_fields: SetupListFieldRow[] | null;
	/** Add-another list: the most rows a client may add; 1 is a plain form. Null for every other type. */
	max_rows: number | null;
	/** Pick from an earlier list: that list question's key. Null for every other type. */
	pick_from: string | null;
	/** Pick from an earlier list: the fewest picks; null asks for one. */
	min_choices: number | null;
	/** Pick from an earlier list: the client puts the picks in order. */
	ordered: boolean;
	/** Use an earlier answer: that question's key. Null for every other type. */
	reuse_from?: string | null;
	/** "Show only if": every condition must hold. Null asks the question always. */
	show_if: SetupShowIfCondition[] | null;
};

/** One box of a list question as the database keeps it. */
export type SetupListFieldRow = Omit<SetupListField, 'fileKinds'> & {
	file_kinds?: SetupFileKind[];
};

/** One stored "show only if" condition (plan §2.1): an earlier answer is one of `values`, or the package includes a service. */
export type SetupShowIfCondition = { fact_key: string; values: string[] } | { service_key: string };

export type SetupEditorStage = {
	key: string;
	title: string;
	description: string;
	service_key: string | null;
	items: SetupEditorItem[];
};

export type SetupEditorVersion = {
	version_id: string;
	version_number: number;
	stages: SetupEditorStage[];
};

export type SetupEditor = {
	published:
		(SetupEditorVersion & { published_at: string; published_by_email: string | null }) | null;
	draft:
		| (SetupEditorVersion & {
				revision: number;
				created_at: string;
				updated_at: string;
				updated_by_email: string | null;
		  })
		| null;
	/** The draft's own questions that clients have answered; their answer type is fixed. */
	answered: string[];
	services: { key: string; name: string; archived: boolean }[];
	history: {
		version_number: number;
		status: 'published' | 'superseded';
		published_at: string;
		published_by_email: string | null;
	}[];
};

/** A stage as the page's form holds it. `key` is null until a new stage is saved; `rowId` tracks the row. */
export type DraftStage = {
	rowId: string;
	key: string | null;
	title: string;
	description: string;
	service_key: string | null;
	/** Questions the stage asks, and whether any is built in. Both come from the saved draft. */
	questions: number;
	builtIn: boolean;
};

export function stageQuestions(stage: SetupEditorStage) {
	const questions = stage.items.filter((item) => item.type === 'question');
	return { questions: questions.length, builtIn: questions.some((item) => item.built_in) };
}

export function draftStages(stages: SetupEditorStage[]): DraftStage[] {
	return stages.map((stage) => ({
		rowId: stage.key,
		key: stage.key,
		title: stage.title,
		description: stage.description,
		service_key: stage.service_key,
		...stageQuestions(stage)
	}));
}

/** What the save sends: the stage list in order. */
export function stagesPayload(stages: DraftStage[]) {
	return stages.map((stage) => ({
		key: stage.key,
		title: stage.title.trim(),
		description: stage.description.trim(),
		service_key: stage.service_key
	}));
}

export function sameStages(a: DraftStage[], b: DraftStage[]) {
	return JSON.stringify(stagesPayload(a)) === JSON.stringify(stagesPayload(b));
}

type ApiError = { error?: string; field_errors?: Record<string, string> };

export class SetupEditorError extends Error {
	constructor(
		message: string,
		readonly status: number,
		readonly body: ApiError & { reason?: string; editor?: SetupEditor }
	) {
		super(message);
	}
}

export function isStaleSetupDraft(error: unknown): error is SetupEditorError {
	return error instanceof SetupEditorError && error.status === 409 && error.body.reason === 'stale';
}

async function send(url: string, method: string, body?: unknown): Promise<SetupEditor> {
	const response = await fetch(url, {
		method,
		headers: body === undefined ? undefined : { 'content-type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	const result = (await response.json().catch(() => ({}))) as ApiError & {
		editor?: SetupEditor;
	};
	if (!response.ok || !result.editor) {
		throw new SetupEditorError(
			result.error ?? 'Something went wrong. Try again.',
			response.status,
			result
		);
	}
	return result.editor;
}

/** A heading or question as the question editor's form holds it. `rowId` tracks the row. */
export type DraftItem = {
	rowId: string;
	type: 'heading' | 'question';
	/** Null until a new question is saved. */
	fact_key: string | null;
	label: string;
	hint: string;
	built_in: boolean;
	required: boolean;
	can_defer: boolean;
	kind: SetupQuestionKind | null;
	/** `value` is null until a new choice is saved. */
	options: { rowId: string; value: string | null; label: string }[];
	allow_other: boolean;
	max_choices: number | null;
	/** Photo or file. Kept while another type is chosen, so switching back loses nothing. */
	file_kinds: SetupFileKind[];
	max_files: number;
	/** Add-another list. Kept while another type is chosen, so switching back loses nothing. */
	list_fields: DraftListField[];
	max_rows: number;
	/**
	 * Pick from an earlier list: the list question's key, or the row id of a list above it in this stage that
	 * has no key yet; null until one is chosen. `max_choices` is the most picks.
	 */
	pick_from: string | null;
	min_choices: number | null;
	ordered: boolean;
	/**
	 * Use an earlier answer: the earlier question's key, or the row id of a question above it in this stage that
	 * has no key yet; null until one is chosen.
	 */
	reuse_from: string | null;
	/** Empty asks the question always. */
	show_if: DraftCondition[];
};

/** One box of a list question as the form holds it. `key` is null until a new box is saved. */
export type DraftListField = {
	rowId: string;
	key: string | null;
	label: string;
	kind: SetupListFieldKind;
	required: boolean;
	/** Pick one. Kept while another type is chosen. */
	options: { rowId: string; value: string | null; label: string }[];
	/** Photo or file. Kept while another type is chosen. */
	file_kinds: SetupFileKind[];
};

let draftRowCount = 0;
/** A row id for something added in the form, unique for the page's life. */
export const newDraftRowId = (prefix: string) => `${prefix}-new-${++draftRowCount}`;

/** A list box as the form holds it, from what the database keeps or a starter. */
export function draftListField(
	field: Partial<SetupListFieldRow> & Pick<SetupListField, 'label' | 'kind' | 'required'>
): DraftListField {
	return {
		rowId: field.key ?? newDraftRowId('box'),
		key: field.key ?? null,
		label: field.label,
		kind: field.kind,
		required: field.required,
		options: (field.options ?? []).map((option) => ({ rowId: option.value, ...option })),
		file_kinds: field.file_kinds ?? [...NEW_FILE_QUESTION.file_kinds]
	};
}

/** The boxes a list starts with: a starter's (Person, Address, Service, Link + note), or one empty box. */
export function starterListFields(starterKey: string | null): DraftListField[] {
	const starter = SETUP_LIST_STARTERS.find((each) => each.key === starterKey);
	return (starter?.fields ?? [{ label: '', kind: 'text' as const, required: true }]).map((field) =>
		draftListField(field)
	);
}

/** What a question just given the list type allows until Jafar changes it. */
export const NEW_LIST_QUESTION = { max_rows: 10 };

/**
 * A "show only if" condition as the form holds it. `source` is the earlier question's key, or the row id of a
 * question above it in this stage that has no key yet; null until one is chosen.
 */
export type DraftCondition =
	| { rowId: string; type: 'answer'; source: string | null; values: string[] }
	| { rowId: string; type: 'service'; service_key: string | null };

function draftConditions(conditions: SetupShowIfCondition[] | null): DraftCondition[] {
	return (conditions ?? []).map((condition, index) =>
		'service_key' in condition
			? { rowId: `condition-${index}`, type: 'service', service_key: condition.service_key }
			: {
					rowId: `condition-${index}`,
					type: 'answer',
					source: condition.fact_key,
					values: [...condition.values]
				}
	);
}

/**
 * What the save sends for one question's conditions. A question above it in this stage that has no key yet is
 * named by its 1-based position, which the database turns into the key it makes on the same save.
 */
function conditionsPayload(conditions: DraftCondition[], items: DraftItem[]) {
	if (conditions.length === 0) return null;
	return conditions.map((condition) => {
		if (condition.type === 'service') return { service_key: condition.service_key ?? '' };
		const index = items.findIndex((item) => item.rowId === condition.source);
		if (index !== -1 && items[index].fact_key === null)
			return { item: index + 1, values: condition.values };
		return { fact_key: condition.source ?? '', values: condition.values };
	});
}

export function draftItems(items: SetupEditorItem[]): DraftItem[] {
	return items.map((item, index) => ({
		rowId: item.fact_key ?? `heading-${index}`,
		type: item.type,
		fact_key: item.fact_key,
		label: item.label,
		hint: item.hint ?? '',
		built_in: item.built_in,
		required: item.required,
		can_defer: item.can_defer,
		kind: item.kind,
		options: (item.options ?? []).map((option) => ({ rowId: option.value, ...option })),
		allow_other: item.allow_other,
		max_choices: item.max_choices,
		file_kinds: item.file_kinds ?? [...NEW_FILE_QUESTION.file_kinds],
		max_files: item.max_files ?? NEW_FILE_QUESTION.max_files,
		list_fields: item.list_fields ? item.list_fields.map(draftListField) : starterListFields(null),
		max_rows: item.max_rows ?? NEW_LIST_QUESTION.max_rows,
		pick_from: item.pick_from ?? null,
		min_choices: item.min_choices ?? null,
		ordered: item.kind === 'pick' ? item.ordered : NEW_PICK_QUESTION.ordered,
		reuse_from: item.reuse_from ?? null,
		show_if: draftConditions(item.show_if)
	}));
}

/** A question just given the pick type asks clients to order their picks until Jafar changes it. */
export const NEW_PICK_QUESTION = { ordered: true };

/**
 * What the save sends for the earlier question a pick or a reuse names: as for a rule, one above with no key
 * yet goes by position.
 */
function earlierQuestionPayload(source: string | null, items: DraftItem[]) {
	if (!source) return null;
	const index = items.findIndex((each) => each.rowId === source);
	if (index !== -1 && items[index].fact_key === null) return { item: index + 1 };
	return { fact_key: source };
}

/** What a question just given the photo or file type accepts until Jafar changes it. */
export const NEW_FILE_QUESTION = { file_kinds: ['photo'] as SetupFileKind[], max_files: 1 };

/** Pick one and tick several: the answer types Jafar writes the choices for. */
export function isChoiceKind(kind: SetupQuestionKind | null) {
	return kind === 'choice' || kind === 'multi_choice';
}

/** What the save sends: the stage's headings and questions in order. */
export function itemsPayload(items: DraftItem[]) {
	return items.map((item) =>
		item.type === 'heading'
			? { type: 'heading' as const, label: item.label.trim(), hint: item.hint.trim() || null }
			: {
					type: 'question' as const,
					fact_key: item.fact_key,
					label: item.label.trim(),
					hint: item.hint.trim() || null,
					required: item.required,
					can_defer: item.can_defer,
					kind: item.built_in ? null : item.kind,
					options:
						!item.built_in && isChoiceKind(item.kind)
							? item.options.map((option) => ({ value: option.value, label: option.label.trim() }))
							: null,
					allow_other: !item.built_in && isChoiceKind(item.kind) && item.allow_other,
					max_choices:
						!item.built_in && (item.kind === 'multi_choice' || item.kind === 'pick')
							? item.max_choices
							: null,
					file_kinds: !item.built_in && item.kind === 'file' ? item.file_kinds : null,
					max_files: !item.built_in && item.kind === 'file' ? item.max_files : null,
					list_fields:
						!item.built_in && item.kind === 'list' ? item.list_fields.map(listFieldPayload) : null,
					max_rows: !item.built_in && item.kind === 'list' ? item.max_rows : null,
					pick_from:
						!item.built_in && item.kind === 'pick'
							? earlierQuestionPayload(item.pick_from, items)
							: null,
					min_choices: !item.built_in && item.kind === 'pick' ? item.min_choices : null,
					ordered: !item.built_in && item.kind === 'pick' && item.ordered,
					reuse_from:
						!item.built_in && item.kind === 'reuse'
							? earlierQuestionPayload(item.reuse_from, items)
							: null,
					show_if: conditionsPayload(item.show_if, items)
				}
	);
}

function listFieldPayload(field: DraftListField) {
	return {
		key: field.key,
		label: field.label.trim(),
		kind: field.kind,
		required: field.required,
		...(field.kind === 'choice'
			? {
					options: field.options.map((option) => ({
						value: option.value,
						label: option.label.trim()
					}))
				}
			: {}),
		...(field.kind === 'file' ? { file_kinds: field.file_kinds } : {})
	};
}

/**
 * A question a "show only if" rule can depend on: one with choices (pick one, tick several, yes/no, yes/no/not
 * sure), or a built-in choice such as country. A tick-several answer matches when any tick does. `options` are the answers it can be matched against; `newChoices` says some are unsaved and so not
 * listed yet.
 */
export type ShowIfSource = {
	id: string;
	label: string;
	/** The stage it is in, when that is an earlier stage. */
	stageTitle: string | null;
	options: SetupChoice[] | 'country';
	newChoices: boolean;
};

type SourceItem = Pick<SetupEditorItem, 'type' | 'fact_key' | 'built_in' | 'kind' | 'label'> & {
	options: { value: string | null; label: string }[] | null;
};

function showIfSource(
	item: SourceItem,
	id: string,
	stageTitle: string | null
): ShowIfSource | null {
	if (item.type !== 'question') return null;
	const source = { id, label: item.label.trim() || 'New question', stageTitle, newChoices: false };
	if (item.built_in) {
		const rules = item.fact_key ? BUILT_IN_FACTS[item.fact_key] : undefined;
		if (rules?.kind === 'country') return { ...source, options: 'country' };
		if ((rules?.kind === 'choice' || rules?.kind === 'choice_other') && rules.options)
			return { ...source, options: rules.options };
		return null;
	}
	if (item.kind === 'yes_no' || item.kind === 'yes_no_unsure')
		return {
			...source,
			options: [
				{ value: 'yes', label: 'Yes' },
				{ value: 'no', label: 'No' },
				...(item.kind === 'yes_no_unsure' ? [{ value: 'not_sure', label: 'Not sure' }] : [])
			]
		};
	if (!isChoiceKind(item.kind)) return null;
	const options = item.options ?? [];
	return {
		...source,
		options: options.flatMap((option) =>
			option.value ? [{ value: option.value, label: option.label.trim() || option.value }] : []
		),
		newChoices: options.some((option) => option.value === null)
	};
}

/**
 * What the question at `index` of this stage can depend on: questions in earlier stages, as last saved, then
 * those above it here, as they stand in the form.
 */
export function showIfSources(
	earlierStages: SetupEditorStage[],
	items: DraftItem[],
	index: number
): ShowIfSource[] {
	const earlier = earlierStages.flatMap((stage) =>
		stage.items.flatMap((item) => {
			const source = item.fact_key ? showIfSource(item, item.fact_key, stage.title) : null;
			return source ? [source] : [];
		})
	);
	const above = items.slice(0, index).flatMap((item) => {
		const source = showIfSource(item, item.rowId, null);
		return source ? [source] : [];
	});
	return [...earlier, ...above];
}

/** An earlier add-another list a pick can choose from. */
export type PickSource = { id: string; label: string; stageTitle: string | null };

/**
 * The lists the question at `index` of this stage can pick from: list questions in earlier stages, as last
 * saved, then those above it here, as they stand in the form.
 */
export function pickSources(
	earlierStages: SetupEditorStage[],
	items: DraftItem[],
	index: number
): PickSource[] {
	const earlier = earlierStages.flatMap((stage) =>
		stage.items.flatMap((item) =>
			item.type === 'question' && item.kind === 'list' && item.fact_key
				? [{ id: item.fact_key, label: item.label, stageTitle: stage.title }]
				: []
		)
	);
	const above = items
		.slice(0, index)
		.flatMap((item) =>
			item.type === 'question' && !item.built_in && item.kind === 'list'
				? [{ id: item.rowId, label: item.label.trim() || 'New list', stageTitle: null }]
				: []
		);
	return [...earlier, ...above];
}

/** An earlier question a reuse can show back to confirm. */
export type ReuseSource = { id: string; label: string; stageTitle: string | null };

/**
 * Whether a question's answer can be shown back to confirm (A5g): built in, or any type but photo or file, pick
 * or reuse; and always asked, since a "show only if" on an earlier answer could hide it. A rule on a service is
 * fine — a client without that service is asked the reuse as a plain question.
 */
function reusable(
	item: Pick<SetupEditorItem, 'type' | 'built_in' | 'kind'>,
	answerRule: boolean
): boolean {
	if (item.type !== 'question' || answerRule) return false;
	return item.built_in || !['file', 'pick', 'reuse', null].includes(item.kind);
}

/**
 * The questions the question at `index` of this stage can reuse: those in earlier stages, as last saved, then
 * those above it here, as they stand in the form.
 */
export function reuseSources(
	earlierStages: SetupEditorStage[],
	items: DraftItem[],
	index: number
): ReuseSource[] {
	const earlier = earlierStages.flatMap((stage) =>
		stage.items.flatMap((item) =>
			item.fact_key &&
			reusable(
				item,
				(item.show_if ?? []).some((condition) => 'fact_key' in condition)
			)
				? [{ id: item.fact_key, label: item.label, stageTitle: stage.title }]
				: []
		)
	);
	const above = items.slice(0, index).flatMap((item) =>
		reusable(
			item,
			item.show_if.some((condition) => condition.type === 'answer')
		)
			? [{ id: item.rowId, label: item.label.trim() || 'New question', stageTitle: null }]
			: []
	);
	return [...earlier, ...above];
}

export function sameItems(a: DraftItem[], b: DraftItem[]) {
	return JSON.stringify(itemsPayload(a)) === JSON.stringify(itemsPayload(b));
}

export const SETUP_QUESTION_KIND_LABELS: Record<SetupQuestionKind, string> = {
	text: 'Short answer',
	longtext: 'Paragraph',
	choice: 'Pick one',
	multi_choice: 'Tick several',
	yes_no: 'Yes or no',
	yes_no_unsure: 'Yes, no or not sure',
	phone: 'Phone number',
	email: 'Email address',
	date: 'Date',
	url: 'Web link',
	number: 'Number',
	money: 'Amount of money',
	percentage: 'Percentage',
	distance: 'Distance',
	duration: 'Length of time',
	colours: 'Colours',
	file: 'Photo or file',
	list: 'Add-another list',
	pick: 'Pick from an earlier list',
	reuse: 'Use an earlier answer'
};

export const fetchSetupEditor = () => send('/api/jafar/setup', 'GET');
export const startSetupDraft = () => send('/api/jafar/setup', 'POST');

type DraftRevision = { version_id: string; revision: number };

export const saveSetupDraft = (draft: DraftRevision, stages: DraftStage[]) =>
	send('/api/jafar/setup/draft', 'PATCH', { ...draft, stages: stagesPayload(stages) });
export const saveSetupStageItems = (draft: DraftRevision, stageKey: string, items: DraftItem[]) =>
	send(`/api/jafar/setup/draft/stages/${encodeURIComponent(stageKey)}`, 'PATCH', {
		...draft,
		items: itemsPayload(items)
	});
export const discardSetupDraft = (draft: DraftRevision) =>
	send('/api/jafar/setup/draft', 'DELETE', draft);
export const publishSetupDraft = (draft: DraftRevision) =>
	send('/api/jafar/setup/draft/publish', 'POST', draft);

/** Who sees a stage, in words. */
export function stageAudience(serviceKey: string | null, services: SetupEditor['services']) {
	if (!serviceKey) return 'Every client';
	const name = services.find((service) => service.key === serviceKey)?.name ?? serviceKey;
	return `Only clients with ${name}`;
}

/** {@link stageAudience} mid-sentence: only the leading word is lowered, so a service keeps its own name. */
const audienceInSentence = (serviceKey: string | null, services: SetupEditor['services']) => {
	const audience = stageAudience(serviceKey, services);
	return audience[0].toLowerCase() + audience.slice(1);
};

const count = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

/** How a kept stage's questions change, in at most three lines. */
function questionChanges(before: SetupEditorStage, after: SetupEditorStage): string[] {
	const questions = (stage: SetupEditorStage) =>
		new Map(
			stage.items.flatMap((item) =>
				item.type === 'question' && item.fact_key ? [[item.fact_key, item] as const] : []
			)
		);
	const old = questions(before);
	const next = questions(after);
	const added = [...next.keys()].filter((key) => !old.has(key)).length;
	const removed = [...old.keys()].filter((key) => !next.has(key)).length;
	const lines: string[] = [];
	if (added) lines.push(`Adds ${count(added, 'question')} to "${after.title}"`);
	if (removed)
		lines.push(
			`Removes ${count(removed, 'question')} from "${after.title}". Answers already given are kept.`
		);
	const strip = (stage: SetupEditorStage, keep: Map<string, unknown>) =>
		JSON.stringify(
			stage.items.filter((item) => item.type === 'heading' || keep.has(item.fact_key ?? ''))
		);
	// Kept questions reworded, retyped or reordered, or headings changed.
	const kept = new Map([...next].filter(([key]) => old.has(key)));
	if (strip(before, kept) !== strip(after, kept))
		lines.push(`Edits questions or headings in "${after.title}"`);
	return lines;
}

/**
 * What publishing changes for clients, line by line, for the publish review. Compares stages by key, so a
 * renamed stage reads as renamed rather than as one removed and one added.
 */
export function publishChanges(
	published: SetupEditorStage[],
	draft: SetupEditorStage[],
	services: SetupEditor['services']
): string[] {
	const lines: string[] = [];
	const before = new Map(published.map((stage) => [stage.key, stage]));
	const after = new Set(draft.map((stage) => stage.key));
	for (const stage of draft) {
		const old = before.get(stage.key);
		if (!old) {
			lines.push(`Adds "${stage.title}" (${audienceInSentence(stage.service_key, services)})`);
			continue;
		}
		if (old.title !== stage.title) lines.push(`Renames "${old.title}" to "${stage.title}"`);
		if (old.description !== stage.description)
			lines.push(`Rewords the description of "${stage.title}"`);
		if (old.service_key !== stage.service_key)
			lines.push(
				`"${stage.title}" now shows to ${audienceInSentence(stage.service_key, services)}`
			);
		lines.push(...questionChanges(old, stage));
	}
	for (const stage of published)
		if (!after.has(stage.key))
			lines.push(`Removes "${stage.title}". Answers already given are kept.`);
	const order = (stages: SetupEditorStage[]) =>
		stages.filter((stage) => before.has(stage.key) && after.has(stage.key)).map((s) => s.key);
	if (order(published).join() !== order(draft).join())
		lines.push('Changes the order of the stages');
	return lines;
}
