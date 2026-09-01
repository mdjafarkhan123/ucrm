// Quote money no longer travels on the version and line rows themselves: `authenticated` lost the grant
// on those columns, so a browser session cannot read them straight off PostgREST. The numbers come back
// from `quote_version_money` and `quote_line_money`, which check `quotes.view_price` and
// `quotes.view_cost` once per call, and are stitched onto the rows here.
//
// A row with no entry in the map is a row this reader may not see money for. It keeps whatever it already
// had, which is the customer document without its numbers — the same payload the route used to build by
// leaving the columns out of the select.

export type QuoteMoneyMap = Record<string, Record<string, unknown>>;

export function asMoneyMap(value: unknown): QuoteMoneyMap {
	return value && typeof value === 'object' && !Array.isArray(value)
		? (value as QuoteMoneyMap)
		: {};
}

export function withMoney<Row extends { id: string }>(rows: Row[], money: QuoteMoneyMap): Row[] {
	return rows.map((row) => ({ ...row, ...(money[row.id] ?? {}) }));
}
