// The Organizations directory's filters, in the one place the page, the query key and the API route all read.
//
// Like the pipeline board's filters, they live in the URL: a refresh, the Back button and a shared link all
// keep what is on screen. The URL is also untrusted input, so a hand-edited or stale link falls back to
// "no filter" for whatever it got wrong instead of putting an error on screen.

export const DIRECTORY_ATTENTION_REASONS = [
	'access_overdue',
	'payment_overdue',
	'renewal_due',
	'expiring_soon',
	'administrator_missing',
	'administrator_ownership_unclear',
	'setup_or_recovery_failed',
	'email_setup_requested'
] as const;
export type DirectoryAttentionReason = (typeof DIRECTORY_ATTENTION_REASONS)[number];

export const DIRECTORY_LIFECYCLES = ['active', 'suspended', 'pending_closure', 'closed'] as const;
export type DirectoryLifecycle = (typeof DIRECTORY_LIFECYCLES)[number];

export const DIRECTORY_BILLING = ['month', 'year'] as const;
export type DirectoryBilling = (typeof DIRECTORY_BILLING)[number];

// `overdue` means the paid-through date has passed; a number is a window of that many days from today.
export const DIRECTORY_RENEWS = ['overdue', '7', '14', '30'] as const;
export type DirectoryRenews = (typeof DIRECTORY_RENEWS)[number];

export const DIRECTORY_TEAM_SIZES = ['solo', 'small', 'large'] as const;
export type DirectoryTeamSize = (typeof DIRECTORY_TEAM_SIZES)[number];

export const DIRECTORY_JOINED = ['7', '30', '90', 'custom'] as const;
export type DirectoryJoined = (typeof DIRECTORY_JOINED)[number];

// The value a Package filter uses for "this organization is on no package".
export const NO_PACKAGE = 'none';

export const DIRECTORY_SEARCH_MAX = 200;
// Package ids in one filter. More than this is not a question a person asks, and it bounds the request.
export const DIRECTORY_PACKAGE_MAX = 20;

export type DirectoryFilters = {
	q: string;
	attention: DirectoryAttentionReason[];
	lifecycle: DirectoryLifecycle[];
	/** Package ids, plus `none` for organizations that are on no package. */
	packages: string[];
	billing: '' | DirectoryBilling;
	renews: '' | DirectoryRenews;
	team: '' | DirectoryTeamSize;
	joined: '' | DirectoryJoined;
	/** Only meaningful while `joined` is `custom`; `YYYY-MM-DD`, either end may be empty. */
	from: string;
	to: string;
};

export const EMPTY_DIRECTORY_FILTERS: DirectoryFilters = {
	q: '',
	attention: [],
	lifecycle: [],
	packages: [],
	billing: '',
	renews: '',
	team: '',
	joined: '',
	from: '',
	to: ''
};

export const DIRECTORY_LABELS = {
	billing: { month: 'Monthly', year: 'Yearly' } satisfies Record<DirectoryBilling, string>,
	renews: {
		overdue: 'Already overdue',
		'7': 'Within 7 days',
		'14': 'Within 14 days',
		'30': 'Within 30 days'
	} satisfies Record<DirectoryRenews, string>,
	team: {
		solo: 'Just one person',
		small: '2 to 5 people',
		large: '6 or more'
	} satisfies Record<DirectoryTeamSize, string>,
	joined: {
		'7': 'Last 7 days',
		'30': 'Last 30 days',
		'90': 'Last 90 days',
		custom: 'Custom range'
	} satisfies Record<DirectoryJoined, string>,
	lifecycle: {
		active: 'Active',
		suspended: 'Suspended',
		pending_closure: 'Closing',
		closed: 'Closed'
	} satisfies Record<DirectoryLifecycle, string>
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

export function isPackageValue(value: string) {
	return value === NO_PACKAGE || UUID.test(value);
}

// A comma-separated list, keeping only what the vocabulary allows, each once.
function readList<Value extends string>(raw: string | null, allowed: readonly Value[]): Value[] {
	if (!raw) return [];
	const seen = new Set<Value>();
	for (const part of raw.split(',')) {
		const value = part.trim() as Value;
		if ((allowed as readonly string[]).includes(value)) seen.add(value);
	}
	return allowed.filter((value) => seen.has(value));
}

function readOne<Value extends string>(raw: string | null, allowed: readonly Value[]): '' | Value {
	return raw && (allowed as readonly string[]).includes(raw) ? (raw as Value) : '';
}

export function readDirectoryFilters(params: URLSearchParams): DirectoryFilters {
	const packages: string[] = [];
	for (const part of (params.get('package') ?? '').split(',')) {
		const value = part.trim().toLowerCase();
		if (isPackageValue(value) && !packages.includes(value)) packages.push(value);
	}
	const day = (key: string) => {
		const raw = params.get(key);
		return raw && ISO_DAY.test(raw) ? raw : '';
	};
	const joined = readOne(params.get('joined'), DIRECTORY_JOINED);
	return {
		q: (params.get('search') ?? '').trim().slice(0, DIRECTORY_SEARCH_MAX),
		attention: readList(params.get('attention_reason'), DIRECTORY_ATTENTION_REASONS),
		lifecycle: readList(params.get('lifecycle'), DIRECTORY_LIFECYCLES),
		packages: packages.slice(0, DIRECTORY_PACKAGE_MAX),
		billing: readOne(params.get('billing'), DIRECTORY_BILLING),
		renews: readOne(params.get('renews'), DIRECTORY_RENEWS),
		team: readOne(params.get('team'), DIRECTORY_TEAM_SIZES),
		joined,
		from: joined === 'custom' ? day('from') : '',
		to: joined === 'custom' ? day('to') : ''
	};
}

// The query string for these filters, leaving out anything at rest so the address stays short and readable.
// The same string is the API request and the cache key's filter part, so the three can never disagree.
export function directoryFilterParams(filters: DirectoryFilters): URLSearchParams {
	const params = new URLSearchParams();
	if (filters.q) params.set('search', filters.q);
	if (filters.attention.length) params.set('attention_reason', filters.attention.join(','));
	if (filters.lifecycle.length) params.set('lifecycle', filters.lifecycle.join(','));
	if (filters.packages.length) params.set('package', filters.packages.join(','));
	if (filters.billing) params.set('billing', filters.billing);
	if (filters.renews) params.set('renews', filters.renews);
	if (filters.team) params.set('team', filters.team);
	if (filters.joined) params.set('joined', filters.joined);
	if (filters.joined === 'custom') {
		if (filters.from) params.set('from', filters.from);
		if (filters.to) params.set('to', filters.to);
	}
	return params;
}

// A custom range needs at least one end before it is a question the API will answer. Until then the list keeps
// showing what it was showing, rather than firing a request that comes back as a validation error.
export function directoryFiltersAreComplete(filters: DirectoryFilters) {
	return filters.joined !== 'custom' || Boolean(filters.from) || Boolean(filters.to);
}

// How many filters are narrowing the list, not counting the search box, which has its own clear button.
export function activeDirectoryFilterCount(filters: DirectoryFilters) {
	return (
		[
			filters.attention.length > 0,
			filters.lifecycle.length > 0,
			filters.packages.length > 0,
			Boolean(filters.billing),
			Boolean(filters.renews),
			Boolean(filters.team),
			Boolean(filters.joined)
		] as boolean[]
	).filter(Boolean).length;
}

// What the directory answers beside the rows: whole-platform counts (never narrowed by the filters in use, so
// a chip keeps showing every option) and how many rows match right now.
export type DirectoryTotals = {
	all: number;
	active: number;
	suspended: number;
	pending_closure: number;
	closed: number;
	no_package: number;
	/** Packages with at least one organization on them, with how many. */
	packages: Array<{ package_id: string; name: string; count: number }>;
	matching: number;
	attention: Record<DirectoryAttentionReason, number>;
};
