// Client onboarding A4 and A5 (plan §2.1, ADR 0006): Jafar's setup editor. Stages and their questions are
// edited as a draft and published; clients see only the published version, each limited to the stages their
// package includes.

import type { SetupQuestionKind } from '$lib/setup/catalogue';

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
};

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
};

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
		options: (item.options ?? []).map((option) => ({ rowId: option.value, ...option }))
	}));
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
						!item.built_in && item.kind === 'choice'
							? item.options.map((option) => ({ value: option.value, label: option.label.trim() }))
							: null
				}
	);
}

export function sameItems(a: DraftItem[], b: DraftItem[]) {
	return JSON.stringify(itemsPayload(a)) === JSON.stringify(itemsPayload(b));
}

export const SETUP_QUESTION_KIND_LABELS: Record<SetupQuestionKind, string> = {
	text: 'Short answer',
	longtext: 'Paragraph',
	choice: 'Pick one',
	yes_no: 'Yes or no',
	phone: 'Phone number',
	email: 'Email address',
	date: 'Date'
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
