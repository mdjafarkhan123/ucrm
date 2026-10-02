// @mentions in a Brief Note. The Note's text keeps the plain "@Name" -- readable anywhere it shows, in an
// email or on the Request page -- and the ids of the people it names travel beside it. These helpers find
// what is being typed after an "@", put a picked name in its place, and work out who the text still names.

export type PickedMention = { id: string; name: string };

/** What is being typed after an "@" right before the caret, or null when the caret is not in a mention.
 *  The "@" must start the text or follow a space or new line, so an email address never opens the list. */
export function mentionQueryAt(
	text: string,
	caret: number
): { start: number; query: string } | null {
	const before = text.slice(0, caret);
	const match = /(^|\s)@([^\s@]{0,40})$/.exec(before);
	if (!match) return null;
	return { start: before.length - match[2].length - 1, query: match[2] };
}

/** The text with "@query" replaced by "@Name ", and where the caret goes after it. */
export function insertMention(
	text: string,
	at: { start: number; query: string },
	name: string
): { text: string; caret: number } {
	const end = at.start + 1 + at.query.length;
	const inserted = `@${name} `;
	// One space is enough: a space already after the caret is not doubled.
	const rest = text.slice(end).replace(/^ /, '');
	return { text: text.slice(0, at.start) + inserted + rest, caret: at.start + inserted.length };
}

/** Teammates whose name matches what was typed: any word of the name starting with it, ignoring case. */
export function matchTeammates<T extends { full_name: string | null }>(
	teammates: T[],
	query: string,
	limit = 6
): T[] {
	const wanted = query.trim().toLowerCase();
	return teammates
		.filter((member) => {
			const name = (member.full_name ?? '').toLowerCase();
			if (!name) return false;
			if (!wanted) return true;
			return (
				name.startsWith(wanted) || name.split(/[\s.@_-]+/).some((word) => word.startsWith(wanted))
			);
		})
		.slice(0, limit);
}

/** The picked people whose "@Name" is still in the text, once each. Deleting the words drops the mention. */
export function mentionsStillIn(text: string, picked: PickedMention[]): string[] {
	const ids = new Set<string>();
	for (const mention of picked) {
		if (mention.name && text.includes(`@${mention.name}`)) ids.add(mention.id);
	}
	return [...ids];
}

/** Splits text into plain runs and "@Name" runs for the given names, longest name first so "@Sam Lee"
 *  is not cut short by a teammate called "Sam". */
export function splitMentions(text: string, names: string[]): { text: string; mention: boolean }[] {
	const usable = [...new Set(names.filter(Boolean))].sort((a, b) => b.length - a.length);
	if (usable.length === 0) return [{ text, mention: false }];
	const escaped = usable.map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
	const pattern = new RegExp(`@(?:${escaped.join('|')})`, 'g');
	const parts: { text: string; mention: boolean }[] = [];
	let last = 0;
	for (const match of text.matchAll(pattern)) {
		const index = match.index ?? 0;
		if (index > last) parts.push({ text: text.slice(last, index), mention: false });
		parts.push({ text: match[0], mention: true });
		last = index + match[0].length;
	}
	if (last < text.length) parts.push({ text: text.slice(last), mention: false });
	return parts;
}
