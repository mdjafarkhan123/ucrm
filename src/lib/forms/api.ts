// Request/booking form builder — browser-side reads and writes (Contractor Settings Part 4B-1).
//
// TanStack Query owns the cache (CLAUDE.md rule 10); this module is only the fetchers and the shared query
// keys. Every write goes through the `/api/settings/forms` routes, which validate with Zod before touching
// the database (rule 12) — nothing here trusts the browser. Response shapes mirror the RPC return objects in
// the two forms migrations exactly.

import type {
	BookingDetail,
	BookingSlot,
	FormContent,
	FormDetail,
	FormListItem,
	FormOutcome,
	FormVersionView
} from './types';

export type FormApiError = Error & {
	fieldErrors?: Record<string, string>;
	/** 'stale_revision' when someone else changed the form since it loaded. */
	reason?: string;
	status?: number;
};

async function throwApiError(response: Response): Promise<never> {
	const result = await response
		.json()
		.catch(
			() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
		);
	const error = new Error(result.error ?? 'That request could not be completed.') as FormApiError;
	error.fieldErrors = result.field_errors ?? {};
	error.reason = result.reason;
	error.status = response.status;
	throw error;
}

async function requestJson<T>(input: string, init?: RequestInit): Promise<T> {
	const response = await fetch(input, {
		...init,
		headers: init?.body ? { 'content-type': 'application/json', ...init.headers } : init?.headers
	});
	if (!response.ok) return throwApiError(response);
	return response.json();
}

// --- Query keys --------------------------------------------------------------------------------------

export const formsKey = (includeArchived = false) =>
	['settings', 'forms', includeArchived] as const;
export const formDetailKey = (id: string) => ['settings', 'forms', 'detail', id] as const;
export const formBookingKey = (id: string) => ['settings', 'forms', 'booking', id] as const;
export const formBookingSlotsKey = (id: string, rangeStart: string, rangeEnd: string) =>
	['settings', 'forms', 'booking', id, 'slots', rangeStart, rangeEnd] as const;

// --- Reads -------------------------------------------------------------------------------------------

export function fetchForms(includeArchived = false) {
	const query = includeArchived ? '?archived=true' : '';
	return requestJson<FormListItem[]>(`/api/settings/forms${query}`);
}

export function fetchFormDetail(id: string) {
	return requestJson<FormDetail>(`/api/settings/forms/${id}`);
}

// --- Booking rules (Part 4B-2c) -----------------------------------------------------------------------

export function fetchFormBooking(id: string) {
	return requestJson<BookingDetail>(`/api/settings/forms/${id}/booking`);
}

export type FormBookingSaveInput = {
	expected_revision: number;
	requires_booking_approval: boolean;
	service_area_enabled: boolean;
	min_notice_minutes: number;
	slot_interval_minutes: number;
	visit_duration_minutes: number;
	arrival_window_minutes: number | null;
	buffer_minutes: number;
	service_ids: string[];
};

export type FormBookingSaveResult = {
	form_id: string;
	revision: number;
	requires_booking_approval: boolean;
	service_area_enabled: boolean;
	min_notice_minutes: number;
	slot_interval_minutes: number;
	visit_duration_minutes: number;
	arrival_window_minutes: number | null;
	buffer_minutes: number;
	service_ids: string[];
};

export function saveFormBooking(id: string, input: FormBookingSaveInput) {
	return requestJson<FormBookingSaveResult>(`/api/settings/forms/${id}/booking`, {
		method: 'PATCH',
		body: JSON.stringify(input)
	});
}

// A short forward-looking window is enough to show "here is what customers would see right now" — the
// preview refreshes after Save (see the slots route's own comment), not on every keystroke.
export function fetchFormBookingSlots(id: string, rangeStart: string, rangeEnd: string) {
	const params = new URLSearchParams({ range_start: rangeStart, range_end: rangeEnd });
	return requestJson<BookingSlot[]>(`/api/settings/forms/${id}/booking/slots?${params}`);
}

// --- Create ------------------------------------------------------------------------------------------

export type FormCreateInput = {
	outcome: FormOutcome;
	name: string;
	title: string;
	description?: string;
};

export type FormCreateResult = {
	form_id: string;
	outcome: FormOutcome;
	name: string;
	is_enabled: boolean;
	is_default: boolean;
	revision: number;
	draft_version_id: string;
	draft_version_number: number;
	draft_revision: number;
};

export function createForm(input: FormCreateInput) {
	return requestJson<FormCreateResult>('/api/settings/forms', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

// --- Save draft ------------------------------------------------------------------------------------

export type FormDraftSaveInput = {
	expected_revision: number;
	title: string;
	description?: string;
	content: FormContent;
};

export type FormDraftSaveResult = {
	form_id: string;
	draft_version_id: string;
	title: string;
	description: string | null;
	content: FormContent;
	/** The draft version's new revision — carry it into the next save/publish. */
	revision: number;
};

export function saveFormDraft(id: string, input: FormDraftSaveInput) {
	return requestJson<FormDraftSaveResult>(`/api/settings/forms/${id}`, {
		method: 'PATCH',
		body: JSON.stringify(input)
	});
}

// --- Lifecycle actions -------------------------------------------------------------------------------

export type FormPublishResult = {
	form_id: string;
	published_version_id: string;
	version_number: number;
	published_at: string;
};

/** `expected_revision` is the draft's revision here, not the form's. */
export function publishFormDraft(id: string, expectedRevision: number) {
	return requestJson<FormPublishResult>(`/api/settings/forms/${id}`, {
		method: 'POST',
		body: JSON.stringify({ action: 'publish', expected_revision: expectedRevision })
	});
}

export type FormReviseResult = {
	form_id: string;
	draft_version_id: string;
	draft_version_number: number;
	revision: number;
};

/** Turn a published form back into an editable draft seeded from what is live. */
export function reviseForm(id: string) {
	return requestJson<FormReviseResult>(`/api/settings/forms/${id}`, {
		method: 'POST',
		body: JSON.stringify({ action: 'revise' })
	});
}

export type FormDefaultResult = { form_id: string; is_default: boolean; revision: number };

export function setFormDefault(id: string, expectedRevision: number) {
	return requestJson<FormDefaultResult>(`/api/settings/forms/${id}`, {
		method: 'POST',
		body: JSON.stringify({ action: 'set_default', expected_revision: expectedRevision })
	});
}

export type FormArchiveResult = { form_id: string; archived: boolean; revision: number };

export function setFormArchived(id: string, archived: boolean, expectedRevision: number) {
	return requestJson<FormArchiveResult>(`/api/settings/forms/${id}`, {
		method: 'POST',
		body: JSON.stringify({
			action: archived ? 'archive' : 'restore',
			expected_revision: expectedRevision
		})
	});
}

export type FormIdentityResult = {
	form_id: string;
	name: string;
	is_enabled: boolean;
	revision: number;
};

export function saveFormIdentity(
	id: string,
	input: { expected_revision: number; name: string; is_enabled: boolean }
) {
	return requestJson<FormIdentityResult>(`/api/settings/forms/${id}`, {
		method: 'POST',
		body: JSON.stringify({ action: 'identity', ...input })
	});
}

// --- Working-copy helpers ----------------------------------------------------------------------------

// The builder edits a deep copy of the loaded draft so nothing mutates the cached query data, and diffs it
// against a baseline to decide whether Save means anything (design inputs.md: Save stays disabled until dirty).
// `help` is normalized to '' here: the API omits it entirely when empty (see toPayloadContent), but the
// builder's help-text field binds two-way against it, and Svelte refuses to bind an $bindable field to a
// source value of `undefined`.
export function cloneContent(content: FormContent): FormContent {
	const clone = structuredClone(content);
	for (const section of clone.sections) {
		for (const question of section.questions) {
			question.help ??= '';
		}
	}
	return clone;
}

export function pickBaselineView(detail: FormDetail): FormVersionView | null {
	return detail.draft ?? detail.published;
}
