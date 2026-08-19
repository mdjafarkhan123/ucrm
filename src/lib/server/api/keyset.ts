// Keyset pagination, never offset, so a page stays cheap however deep the list goes and a row cannot be
// skipped or shown twice when rows are added while someone is reading.
//
// Cursor format: "<sort column's value>|<id>". The id breaks ties, so two rows sharing a timestamp or a
// title still have one stable order.
export function readCursor(raw: string | null | undefined) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const value = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (id.length === 0) return null;
	return { value, id };
}

export function encodeCursor(value: unknown, id: string) {
	return `${value}|${id}`;
}

// PostgREST's or= filter string treats comma and parenthesis as syntax, and a title can contain either —
// quoting (and escaping backslash and quote inside it) keeps a cursor value from being parsed as extra
// filter clauses.
export function quoteFilterValue(value: string) {
	return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}
