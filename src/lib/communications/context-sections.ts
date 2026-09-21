// The tabs of the inbox's customer context rail that load their own list of the customer's records. The
// Contact tab is not here: it needs only the client itself, which the rail always loads first.
//
// Shared by the browser (which tabs to draw, what to call them) and the route (which permission gates a
// tab), so the two can never disagree about what exists.
export const CONTEXT_SECTIONS = [
	'properties',
	'requests',
	'quotes',
	'jobs',
	'invoices',
	'pipeline'
] as const;

export type ContextSection = (typeof CONTEXT_SECTIONS)[number];

export const CONTEXT_SECTION_LABELS: Record<ContextSection, string> = {
	properties: 'Properties',
	requests: 'Requests',
	quotes: 'Quotes',
	jobs: 'Jobs',
	invoices: 'Invoices',
	pipeline: 'Pipeline'
};

// What a member must hold to see a tab at all. Properties and requests need nothing beyond being able to
// open the conversation (`customers.view`), matching the rest of the app.
export const CONTEXT_SECTION_PERMISSIONS: Record<ContextSection, string | null> = {
	properties: null,
	requests: null,
	quotes: 'quotes.view',
	jobs: 'jobs.view',
	invoices: 'invoices.view',
	pipeline: 'pipeline.view'
};

// The permission that lets a member see the money on a tab, for the tabs that carry any.
export const CONTEXT_SECTION_PRICE_PERMISSIONS: Partial<Record<ContextSection, string>> = {
	quotes: 'quotes.view_price',
	jobs: 'jobs.view_price',
	invoices: 'invoices.view_price'
};

// A rail is a glance, not a list page: the latest few, and a way to the client for the rest.
export const CONTEXT_SECTION_LIMIT = 6;

export function isContextSection(value: string | null): value is ContextSection {
	return (CONTEXT_SECTIONS as readonly string[]).includes(value ?? '');
}
