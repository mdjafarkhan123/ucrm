// Client onboarding A5g: reuse and confirm an earlier answer (plan §2.1; the blueprint's "Reuse + confirmation",
// such as "Which phone should the website show?"). The client sees what they already told us and picks
// "Yes, use this" or "Use a different one here" — a checkout's "billing address same as delivery".
//
// Yes travels and is stored as {"same_as": "<the earlier question's key>"}: the fact is kept once, so a later
// change to it carries through. A different answer is an ordinary answer with the earlier question's rules,
// kept for this question only.

/** The answer text that means "the same as the earlier answer". */
export function setupReuseValue(sourceKey: string): string {
	return JSON.stringify({ same_as: sourceKey });
}

/** The earlier question a stored or typed answer says it is the same as, or null for any other answer. */
export function setupReuseSource(raw: string | null | undefined): string | null {
	if (!raw?.startsWith('{')) return null;
	try {
		const value = JSON.parse(raw) as unknown;
		if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
		const keys = Object.keys(value);
		const source = (value as { same_as?: unknown }).same_as;
		return keys.length === 1 && typeof source === 'string' ? source : null;
	} catch {
		return null;
	}
}
