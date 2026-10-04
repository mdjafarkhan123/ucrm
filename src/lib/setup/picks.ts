// Client onboarding A5f: a pick from an earlier list (plan §2.1; the blueprint's "Ordered selection", such as
// "Which 3–5 services should Uplift promote first?"). The client chooses among the rows they already added to
// an earlier add-another list (A5e) — survey tools call this carrying choices forward — and, when Jafar asks
// for it, puts them in order, most important first.
//
// The answer travels and is stored as the picked rows' ids in order: ["a1b2c3d4", …]. Nothing is copied, so a
// row renamed later is still the one picked; a row removed from the list drops out of every pick of it.

import { setupListCellText, type SetupListRow } from '$lib/setup/lists';

type Parsed<T> = { value: T; error: null } | { value: null; error: string };

export type SetupPickRules = { minChoices?: number; maxChoices?: number };

/** The fewest picks an answer needs: Jafar's minimum, or every row when the list holds fewer. */
export function setupPickMinimum(rules: SetupPickRules, rowCount: number): number {
	return Math.min(rules.minChoices ?? 1, rowCount);
}

/** What the client is asked to pick, in words: "Pick 3 to 5.", "Pick up to 2.", "Pick at least 3." */
export function setupPickInstruction(rules: SetupPickRules, rowCount: number): string {
	const least = setupPickMinimum(rules, rowCount);
	const most = rules.maxChoices ? Math.min(rules.maxChoices, rowCount) : null;
	if (least > 1 && least === rowCount && (most === null || most === rowCount))
		return `Pick all ${rowCount}.`;
	if (most !== null && least === most) return most === 1 ? 'Pick one.' : `Pick ${most}.`;
	if (most !== null && least > 1) return `Pick ${least} to ${most}.`;
	if (most !== null) return most === 1 ? 'Pick one.' : `Pick up to ${most}.`;
	return least > 1 ? `Pick at least ${least}.` : 'Pick as many as apply.';
}

function json(raw: string): unknown {
	try {
		return JSON.parse(raw);
	} catch {
		return undefined;
	}
}

/**
 * A pick answer: a list of distinct row ids, each a row the earlier list holds now, and no more than Jafar's
 * maximum. Fewer than {@link setupPickMinimum} still saves, so picking autosaves as it goes; "Mark as done"
 * asks for the rest (`setupAnswerShortfall` in `$lib/setup/catalogue`).
 */
export function parseSetupPick(
	raw: string,
	rows: readonly SetupListRow[],
	rules: SetupPickRules
): Parsed<string[]> {
	const fail = (error: string): Parsed<never> => ({ value: null, error });
	const ids = json(raw);
	if (!Array.isArray(ids) || ids.some((id) => typeof id !== 'string'))
		return fail('This answer could not be read. Reload the page and try again.');
	if (ids.length === 0) return fail('Pick at least one.');
	const held = new Set(rows.map((row) => row.id));
	if (new Set(ids).size !== ids.length)
		return fail('One choice is picked twice. Reload the page and try again.');
	if (ids.some((id) => !held.has(id)))
		return fail('One of these is no longer in your list. Reload the page and try again.');
	if (rules.maxChoices && ids.length > rules.maxChoices)
		return fail(`Pick no more than ${rules.maxChoices}.`);
	return { value: ids as string[], error: null };
}

/** The ids a stored pick holds, or none when it holds none. */
export function setupPickIds(raw: string | null | undefined): string[] {
	if (!raw?.startsWith('[')) return [];
	const ids = json(raw);
	return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === 'string') : [];
}

/** A pick with the rows the list no longer holds left out, in the same order. */
export function keptSetupPickIds(ids: readonly string[], rows: readonly SetupListRow[]): string[] {
	const held = new Set(rows.map((row) => row.id));
	return ids.filter((id) => held.has(id));
}

/** What a row is called in a pick: its first box, or its place in the list when that box is empty. */
export function setupPickRowName(row: SetupListRow, index: number, nameKey?: string): string {
	const name = nameKey ? setupListCellText(row.values[nameKey]) : '';
	return name && !name.startsWith('[') && !name.startsWith('{') ? name : `Entry ${index + 1}`;
}
