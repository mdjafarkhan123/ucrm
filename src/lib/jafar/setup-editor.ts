// Client onboarding A4 (plan §2.1, ADR 0006): Jafar's setup stage editor. Stages are edited as a draft and
// published; clients see only the published version, each limited to the stages their package includes.

export type SetupEditorItem = {
	type: 'heading' | 'question';
	fact_key: string | null;
	label: string;
	built_in: boolean;
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

export const fetchSetupEditor = () => send('/api/jafar/setup', 'GET');
export const startSetupDraft = () => send('/api/jafar/setup', 'POST');

type DraftRevision = { version_id: string; revision: number };

export const saveSetupDraft = (draft: DraftRevision, stages: DraftStage[]) =>
	send('/api/jafar/setup/draft', 'PATCH', { ...draft, stages: stagesPayload(stages) });
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
