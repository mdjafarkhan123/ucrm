import type { StoredQuoteStatus } from './statuses';

// The Quotes list's overview figures and the words built around them. Every number is worked out by the
// database (`quote_list_overview`, `quote_list_activity`); this module only gives the answer a known shape
// and turns it into the short phrases the Pencil frame shows, so both the server and the page agree.

export type OpenQuoteStatus = 'draft' | 'awaiting_response' | 'changes_requested' | 'approved';

export type QuoteListOverview = {
	open_count: number;
	/** Null for a reader without quotes.view_price, like every other money figure. */
	open_minor: number | null;
	status_minor: Record<OpenQuoteStatus, number> | null;
	/** The 30 calendar days ending today where the business is, as YYYY-MM-DD. */
	window_start: string;
	window_end: string;
	sent_count: number;
	sent_minor: number | null;
	converted_count: number;
	converted_minor: number | null;
	/** Converted out of sent, in hundredths of a percent; null when nothing was sent in the window. */
	rate_basis_points: number | null;
	prior_rate_basis_points: number | null;
	waiting_over_7_days: number;
	sent_not_opened: number;
	/** The days the active follow-up emails go out on, counted from the send; null when none is on. */
	follow_up_days: number[] | null;
};

export const quoteListOverviewKey = ['quotes', 'counts', 'overview'] as const;

function count(value: unknown): number {
	const number = Number(value);
	return Number.isFinite(number) ? number : 0;
}
function maybeNumber(value: unknown): number | null {
	if (value === null || value === undefined) return null;
	const number = Number(value);
	return Number.isFinite(number) ? number : null;
}

const OPEN_STATUSES: OpenQuoteStatus[] = [
	'draft',
	'awaiting_response',
	'changes_requested',
	'approved'
];

// The database answer, with every field present and every number a number, whatever came back.
export function readQuoteListOverview(raw: unknown): QuoteListOverview {
	const value = (raw ?? {}) as Record<string, unknown>;
	const statusRaw = value.status_minor as Record<string, unknown> | null | undefined;
	return {
		open_count: count(value.open_count),
		open_minor: maybeNumber(value.open_minor),
		status_minor: statusRaw
			? (Object.fromEntries(
					OPEN_STATUSES.map((status) => [status, count(statusRaw[status])])
				) as Record<OpenQuoteStatus, number>)
			: null,
		window_start: String(value.window_start ?? ''),
		window_end: String(value.window_end ?? ''),
		sent_count: count(value.sent_count),
		sent_minor: maybeNumber(value.sent_minor),
		converted_count: count(value.converted_count),
		converted_minor: maybeNumber(value.converted_minor),
		rate_basis_points: maybeNumber(value.rate_basis_points),
		prior_rate_basis_points: maybeNumber(value.prior_rate_basis_points),
		waiting_over_7_days: count(value.waiting_over_7_days),
		sent_not_opened: count(value.sent_not_opened),
		follow_up_days: Array.isArray(value.follow_up_days)
			? value.follow_up_days.map(count).filter((day) => day > 0)
			: null
	};
}

export async function fetchQuoteListOverview(): Promise<QuoteListOverview> {
	const response = await fetch('/api/quotes/overview');
	if (!response.ok) {
		const error = new Error('The overview could not be loaded.') as Error & { status?: number };
		error.status = response.status;
		throw error;
	}
	return response.json();
}

/** "42%" from basis points, whole percent. */
export function percentText(basisPoints: number): string {
	return `${Math.round(basisPoints / 100)}%`;
}

/** How this month's rate compares with the 30 days before, or null when there is nothing to compare. */
export function conversionChange(
	rate: number | null,
	prior: number | null
): { direction: 'up' | 'down' | 'same'; text: string } | null {
	if (rate === null || prior === null) return null;
	const now = Math.round(rate / 100);
	const before = Math.round(prior / 100);
	if (now > before) return { direction: 'up', text: `Up from ${before}%` };
	if (now < before) return { direction: 'down', text: `Down from ${before}%` };
	return { direction: 'same', text: 'Same as before' };
}

/** "Follow-up emails on, day 3 and day 7", or the off state. */
export function followUpText(days: number[] | null): string {
	if (!days || days.length === 0) return 'Follow-up emails off';
	const parts = days.map((day) => `day ${day}`);
	const list =
		parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(', ')} and ${parts.at(-1)}`;
	return `Follow-up emails on, ${list}`;
}

// --- The line under a row's status --------------------------------------------------------------------

export type QuoteRowFacts = {
	status: StoredQuoteStatus;
	sent_at: string | null;
	decision: 'approved' | 'declined' | null;
	decided_at: string | null;
	decision_method: 'offline_verbal' | 'online' | 'in_person' | null;
	archived_at: string | null;
	view_count: number;
	changes_requested_at: string | null;
	job: { id: string; job_number: number } | null;
};

export type QuoteStatusDetail = {
	text: string;
	/** Set on a converted quote whose job this person may open: the link follows `text`. */
	job?: { id: string; label: string };
	/** The quote was sent and the client has not opened it. */
	unopened?: boolean;
};

const METHOD_WORDS: Record<NonNullable<QuoteRowFacts['decision_method']>, string> = {
	online: 'online',
	in_person: 'in person',
	offline_verbal: 'verbally'
};

/** "Sent Oct 13 · opened 2×", "Client asked Oct 13", "Approved online Oct 12", "Became Job #1042"... */
export function quoteStatusDetail(
	quote: QuoteRowFacts,
	day: (iso: string) => string
): QuoteStatusDetail | null {
	switch (quote.status) {
		case 'draft':
			return { text: quote.sent_at ? 'Revision not sent yet' : 'Not sent yet' };
		case 'awaiting_response': {
			if (!quote.sent_at) return null;
			const opened = quote.view_count > 0 ? `opened ${quote.view_count}×` : 'not opened';
			return {
				text: `Sent ${day(quote.sent_at)} · ${opened}`,
				unopened: quote.view_count === 0
			};
		}
		case 'changes_requested':
			return quote.changes_requested_at
				? { text: `Client asked ${day(quote.changes_requested_at)}` }
				: { text: 'Client asked for edits' };
		case 'approved':
		case 'declined': {
			const verb = quote.status === 'approved' ? 'Approved' : 'Declined';
			if (!quote.decided_at) return null;
			const method =
				quote.status === 'approved' && quote.decision_method
					? ` ${METHOD_WORDS[quote.decision_method]}`
					: '';
			return { text: `${verb}${method} ${day(quote.decided_at)}` };
		}
		case 'converted':
			return quote.job
				? {
						text: 'Became',
						job: { id: quote.job.id, label: `Job #${quote.job.job_number}` }
					}
				: { text: 'Became a job' };
		case 'archived':
			return quote.archived_at ? { text: `Archived ${day(quote.archived_at)}` } : null;
		default:
			return null;
	}
}
