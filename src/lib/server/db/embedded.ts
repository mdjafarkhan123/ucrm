// A PostgREST embed across a composite foreign key -- (organization_id, id), the shape every tenant table
// here uses -- is a single row at runtime, but the generated types cannot prove it is one-to-one and call it
// an array. This takes either shape and hands back the one row, or null.
export function embeddedOne<T>(value: T | T[] | null | undefined): T | null {
	if (Array.isArray(value)) return value[0] ?? null;
	return value ?? null;
}
