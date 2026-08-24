import type { StatusTone } from '$lib/components/work/types';

// The quote statuses, in one place both the server and the browser can read. The database enum is the
// real source; this file says what each one is called and which tone it wears. `quotes.schema.ts`
// re-exports the list so a server route and a page can never disagree about what exists.
export const STORED_QUOTE_STATUSES = [
	'draft',
	'awaiting_response',
	'changes_requested',
	'approved',
	'declined',
	'archived',
	'converted'
] as const;

export type StoredQuoteStatus = (typeof STORED_QUOTE_STATUSES)[number];

export const QUOTE_STATUS_LABELS: Record<StoredQuoteStatus, string> = {
	draft: 'Draft',
	awaiting_response: 'Awaiting response',
	changes_requested: 'Changes requested',
	approved: 'Approved',
	declined: 'Declined',
	archived: 'Archived',
	converted: 'Converted'
};

// Seven statuses onto the design system's five tones. Changes requested is a warning rather than a
// failure — the client still wants the work, they just want it different.
export const QUOTE_STATUS_TONES: Record<StoredQuoteStatus, StatusTone> = {
	draft: 'inactive',
	awaiting_response: 'informative',
	changes_requested: 'warning',
	approved: 'success',
	declined: 'critical',
	archived: 'inactive',
	converted: 'success'
};

// The four the office acts on, in the order the Overview card lists them.
export const QUOTE_OVERVIEW_STATUSES = [
	'draft',
	'awaiting_response',
	'changes_requested',
	'approved'
] as const;
