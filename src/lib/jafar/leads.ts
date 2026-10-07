import type { DealStage } from './deals';

// Uplift's Leads (Jafar business management B1): the words the list, the add form, the query key and the API
// route all share. Like the Organizations directory, the list's filters live in the URL, so a refresh, the Back
// button and a shared link keep what is on screen; a hand-edited link falls back to "no filter" for whatever it
// got wrong instead of putting an error on screen.

export const LEAD_STATUSES = [
	'new',
	'researching',
	'ready_for_review',
	'approved',
	'later',
	'unsuitable'
] as const;
export type LeadStatus = (typeof LEAD_STATUSES)[number];

/** Approved is reached only by approving contact details in the review queue, never chosen from a list. */
export const LEAD_SETTABLE_STATUSES = LEAD_STATUSES.filter(
	(status): status is Exclude<LeadStatus, 'approved'> => status !== 'approved'
) as [Exclude<LeadStatus, 'approved'>, ...Exclude<LeadStatus, 'approved'>[]];

export const LEAD_SOURCES = [
	'own_website',
	'google_maps',
	'directory',
	'social',
	'referral',
	'contacted_us',
	'event',
	'other'
] as const;
export type LeadSource = (typeof LEAD_SOURCES)[number];

export const CONTACT_METHOD_KINDS = [
	'email',
	'phone',
	'whatsapp',
	'instagram',
	'facebook',
	'linkedin',
	'contact_form',
	'other'
] as const;
export type ContactMethodKind = (typeof CONTACT_METHOD_KINDS)[number];

export const LEAD_SORTS = ['newest', 'next_action'] as const;
export type LeadSort = (typeof LEAD_SORTS)[number];

export const LEAD_SEARCH_MAX = 200;
export const LEAD_CONTACT_METHODS_MAX = 10;

export const LEAD_STATUS_LABELS: Record<LeadStatus, string> = {
	new: 'New',
	researching: 'Researching',
	ready_for_review: 'Ready for review',
	approved: 'Approved to contact',
	later: 'Saved for later',
	unsuitable: 'Unsuitable'
};

export const LEAD_STATUS_TONES: Record<
	LeadStatus,
	'informative' | 'warning' | 'success' | 'inactive'
> = {
	new: 'informative',
	researching: 'informative',
	ready_for_review: 'warning',
	approved: 'success',
	later: 'inactive',
	unsuitable: 'inactive'
};

export const LEAD_SOURCE_LABELS: Record<LeadSource, string> = {
	own_website: 'Their own website',
	google_maps: 'Google Maps',
	directory: 'Trade directory',
	social: 'Social media',
	referral: 'Referral',
	contacted_us: 'They contacted us',
	event: 'Event',
	other: 'Other'
};

export const CONTACT_METHOD_LABELS: Record<ContactMethodKind, string> = {
	email: 'Email',
	phone: 'Phone',
	whatsapp: 'WhatsApp',
	instagram: 'Instagram',
	facebook: 'Facebook',
	linkedin: 'LinkedIn',
	contact_form: 'Website contact form',
	other: 'Other'
};

export const LEAD_SORT_LABELS: Record<LeadSort, string> = {
	newest: 'Newest added',
	next_action: 'Next action due'
};

export type LeadFilters = {
	q: string;
	statuses: LeadStatus[];
	countries: string[];
	sources: LeadSource[];
	sort: LeadSort;
	/** B4: show the businesses that have a Deal instead of the ones still being worked as Leads. */
	inDeal: boolean;
};

export const EMPTY_LEAD_FILTERS: LeadFilters = {
	q: '',
	statuses: [],
	countries: [],
	sources: [],
	sort: 'newest',
	inDeal: false
};

const COUNTRY_CODE = /^[A-Z]{2}$/;
// More countries than this in one filter is not a question a person asks, and it bounds the request.
export const LEAD_COUNTRY_FILTER_MAX = 30;

export function isCountryCode(value: string) {
	return COUNTRY_CODE.test(value);
}

// A comma-separated list, keeping only what the vocabulary allows, each once, in the vocabulary's order.
function readList<Value extends string>(raw: string | null, allowed: readonly Value[]): Value[] {
	if (!raw) return [];
	const seen = new Set(raw.split(',').map((part) => part.trim()));
	return allowed.filter((value) => seen.has(value));
}

export function readLeadFilters(params: URLSearchParams): LeadFilters {
	const countries: string[] = [];
	for (const part of (params.get('country') ?? '').split(',')) {
		const value = part.trim().toUpperCase();
		if (isCountryCode(value) && !countries.includes(value)) countries.push(value);
	}
	const sort = params.get('sort');
	return {
		q: (params.get('search') ?? '').trim().slice(0, LEAD_SEARCH_MAX),
		statuses: readList(params.get('status'), LEAD_STATUSES),
		countries: countries.slice(0, LEAD_COUNTRY_FILTER_MAX),
		sources: readList(params.get('source'), LEAD_SOURCES),
		sort: sort === 'next_action' ? 'next_action' : 'newest',
		inDeal: params.get('deal') === 'with'
	};
}

// The query string for these filters, leaving out anything at rest. The same string is the page address, the
// API request and the cache key's filter part, so the three can never disagree.
export function leadFilterParams(filters: LeadFilters): URLSearchParams {
	const params = new URLSearchParams();
	if (filters.q) params.set('search', filters.q);
	if (filters.statuses.length) params.set('status', filters.statuses.join(','));
	if (filters.countries.length) params.set('country', filters.countries.join(','));
	if (filters.sources.length) params.set('source', filters.sources.join(','));
	if (filters.sort !== 'newest') params.set('sort', filters.sort);
	if (filters.inDeal) params.set('deal', 'with');
	return params;
}

export function hasLeadFilters(filters: LeadFilters) {
	return Boolean(
		filters.q || filters.statuses.length || filters.countries.length || filters.sources.length
	);
}

let regionNames: Intl.DisplayNames | null = null;

/** "GB" -> "United Kingdom", from the browser's own names, so the list ships no country table. */
export function countryName(code: string) {
	try {
		regionNames ??= new Intl.DisplayNames(['en'], { type: 'region' });
		return regionNames.of(code) ?? code;
	} catch {
		return code;
	}
}

export type LeadContactMethod = { kind: ContactMethodKind; value: string };

export type LeadListItem = {
	id: string;
	business_name: string;
	country_code: string;
	trade: string;
	source: LeadSource;
	website_host: string | null;
	contact_name: string | null;
	contact_methods: LeadContactMethod[];
	lead_status: LeadStatus;
	next_action: string | null;
	next_action_due_on: string | null;
	created_at: string;
	/** B4: the stage of the business's latest Deal, when it has one. */
	deal_stage: DealStage | null;
};

export type LeadListTotals = {
	all: number;
	/** B4: businesses with a Deal, open or Lost; they leave the default list. */
	in_deal: number;
	matching: number;
	statuses: Partial<Record<LeadStatus, number>>;
	countries: Array<{ code: string; count: number }>;
	sources: Partial<Record<LeadSource, number>>;
};

export type LeadListPage = {
	leads: LeadListItem[];
	next_cursor: string | null;
	totals: LeadListTotals;
};

export type LeadDuplicate = {
	kind: 'lead' | 'application' | 'organization';
	id: string;
	name: string;
	country_code: string | null;
	matched_on: Array<'website' | 'email' | 'phone' | 'name'>;
};
