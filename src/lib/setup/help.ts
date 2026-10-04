// Client onboarding C3c: Uplift's to-do — the questions a client answered "I need Uplift's help" in their newest
// send, and the answers Uplift found (plan §2, §4, §10 journey 4; ADR 0005 decision 4). The to-do is read from
// the client's own answers, so an item is open exactly while that answer is "need help" and Uplift has not
// answered it; the client's "need help" itself is never changed. Jafar's choices of 2026-10-04: Uplift answers in
// the same kind of box the client had, a written note for photos, files and lists, and the client sees it.

import type { SetupAnswers, SetupFact, SetupFactKind } from '$lib/setup/catalogue';
import type { SetupCheckSection } from '$lib/setup/check';
import { setupAnswerLines } from '$lib/setup/answer-lines';

export const SETUP_HELP_NOTE_MAX = 2000;

/** Answers Uplift writes in words: what it did with photos, files or rows lives outside the client's account. */
const NOTE_KINDS = new Set<SetupFactKind>(['file', 'protected_file', 'list', 'pick']);

/** Uplift answers this question in the client's own box, or in a written note. */
export const setupHelpAnswerForm = (fact: SetupFact): 'box' | 'note' =>
	NOTE_KINDS.has(fact.kind) ? 'note' : 'box';

/** Uplift's answer to one help request, as both pages show it. */
export type SetupHelpAnswer = {
	/** The answer as the client's own box holds it, as text; null for a written note. */
	value: string | null;
	note: string | null;
	/** The value in words; empty for a note. */
	lines: string[];
	recorded_by_email: string;
	recorded_at: string;
};

/** A stored row, its value read as text the way `setupAnswerFromRow` reads a client's. */
export function setupHelpAnswerFromRow(
	fact: SetupFact | undefined,
	row: { value: unknown; note: string | null; recorded_by_email: string; recorded_at: string }
): SetupHelpAnswer {
	const value =
		typeof row.value === 'string'
			? row.value
			: row.value == null
				? null
				: JSON.stringify(row.value);
	return {
		value,
		note: row.note,
		lines: fact && value ? setupAnswerLines(fact, value) : [],
		recorded_by_email: row.recorded_by_email,
		recorded_at: row.recorded_at
	};
}

/** One help request on Uplift's to-do. */
export type SetupHelpItem = {
	section_key: string;
	section_title: string;
	fact_key: string;
	label: string;
	/** The question as the send asked it, for Uplift's answer box. */
	fact: SetupFact;
	/** Uplift answers in the client's own box, or in a written note. */
	form: 'box' | 'note';
	/** What the client said beside "I need Uplift's help". */
	client_note: string | null;
	answer: SetupHelpAnswer | null;
};

/** Every help request in a send read back by task, open ones first, each in task order. */
export function setupHelpItems(
	sections: readonly SetupCheckSection[],
	facts: ReadonlyMap<string, SetupFact>,
	answers: Readonly<Record<string, SetupHelpAnswer>>
): SetupHelpItem[] {
	const items = sections.flatMap((section) =>
		section.items.flatMap((item) => {
			const fact = facts.get(item.key);
			if (item.state !== 'need_help' || !fact) return [];
			return [
				{
					section_key: section.key,
					section_title: section.title,
					fact_key: item.key,
					label: item.label,
					fact,
					form: setupHelpAnswerForm(fact),
					client_note: item.note,
					answer: answers[item.key] ?? null
				}
			];
		})
	);
	return [...items.filter((item) => !item.answer), ...items.filter((item) => item.answer)];
}

/** The help answers that apply to `answers`: only questions answered "I need Uplift's help" there. */
export function applicableHelpAnswers(
	all: Readonly<Record<string, SetupHelpAnswer>>,
	answers: SetupAnswers
): Record<string, SetupHelpAnswer> {
	return Object.fromEntries(
		Object.entries(all).filter(([key]) => answers[key]?.availability === 'need_help')
	);
}
