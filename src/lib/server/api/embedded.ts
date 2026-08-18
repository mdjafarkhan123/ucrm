// PostgREST returns one row for a many-to-one embed, but the generated types describe our composite
// foreign keys as arrays. This unwraps whichever shape arrives.
export function embeddedOne<T>(value: T | T[] | null | undefined): T | null {
	if (value === null || value === undefined) return null;
	return Array.isArray(value) ? (value[0] ?? null) : value;
}
