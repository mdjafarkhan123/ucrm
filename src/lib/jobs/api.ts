import type { JobDerivedStatus, JobType } from './statuses';

export type JobWriteError = Error & {
	fieldErrors?: Record<string, string>;
	reason?: string;
};

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as JobWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return response.json();
}

export type JobSortKey = 'created' | 'number';

export type JobListFilters = {
	search: string;
	statuses: JobDerivedStatus[];
	types: JobType[];
	/** ISO instants, already widened to cover the whole day the person picked. */
	created_from: string;
	created_to: string;
	sort: JobSortKey;
	dir: 'asc' | 'desc';
};

export type JobListItem = {
	id: string;
	job_number: number;
	title: string;
	job_type: JobType;
	is_as_needed: boolean;
	/** Worked out in the database, never in the browser. */
	derived_status: JobDerivedStatus;
	currency_code: string;
	created_at: string;
	contract_end_date: string | null;
	from_quote: boolean;
	client: { id: string; display_name: string | null; company_name: string | null } | null;
	property: {
		id: string;
		label: string | null;
		address_line1: string | null;
		city: string | null;
		state_region: string | null;
		postal_code: string | null;
	} | null;
	/** Null when this person may not see money at all — the table shows a dash, never a wrong number. */
	total_minor: number | null;
};

export type JobListPage = {
	jobs: JobListItem[];
	// Null means this was the last page. Keyset paging, so there is no page number to jump to.
	next_cursor: string | null;
	locale: string;
};

export type JobStatusCounts = Record<JobDerivedStatus, number>;

export const jobsListKey = (filters: JobListFilters) => ['jobs', 'list', filters] as const;
export const jobCountsKey = ['jobs', 'counts'] as const;

export async function fetchJobs(filters: JobListFilters, cursor?: string): Promise<JobListPage> {
	const params = new URLSearchParams();
	if (filters.search) params.set('search', filters.search);
	// One comma-joined value, which is what the list route splits on.
	if (filters.statuses.length > 0) params.set('status', filters.statuses.join(','));
	if (filters.types.length > 0) params.set('type', filters.types.join(','));
	if (filters.created_from) params.set('created_from', filters.created_from);
	if (filters.created_to) params.set('created_to', filters.created_to);
	if (filters.sort !== 'created') params.set('sort', filters.sort);
	if (filters.dir !== 'desc') params.set('dir', filters.dir);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/jobs?${params.toString()}`);
	return readOrThrow<JobListPage>(response, 'Jobs could not be loaded.');
}

export type JobOverview = {
	counts: JobStatusCounts;
	currency_code: string;
	locale: string;
};

export async function fetchJobOverview(): Promise<JobOverview> {
	const response = await fetch('/api/jobs/counts');
	return readOrThrow<JobOverview>(response, 'The overview could not be loaded.');
}

// --- Creating a one-off job -------------------------------------------------------------------------------

// One priced line of the job's scope, in the order the editor lists them. Position is set from the array
// index at send time, so the browser never has to keep it in sync while lines are dragged or removed.
export type JobScopeLineInput = {
	position: number;
	category: 'product' | 'service';
	is_labor: boolean;
	source_catalog_item_id: string | null;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
	// Only ever carried forward, never chosen here: a line converted from a quote keeps its photo through a
	// rewrite of the scope. Attaching a photo to a job line is Part 15's job.
	image_attachment_id?: string | null;
};

// One appointment. `visit_date` is null for a "schedule later" visit; times are null for an anytime or an
// unscheduled visit. The three shapes the database stores are all expressible here.
export type JobVisitInput = {
	position: number;
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	title: string | null;
	instructions: string | null;
	assignee_ids: string[];
};

// The repeat rule behind a recurring job, exactly as the form holds it and the server stores it. Weekdays are
// 0 = Sunday through 6 = Saturday. `ordinal_week` is 1st through 4th, or 5 meaning the last one in the month.
export type JobRecurrenceInput = {
	frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
	interval_count: number;
	weekdays: number[];
	monthly_mode: 'day_of_month' | 'last_day' | 'day_of_week' | null;
	month_day: number | null;
	ordinal_week: number | null;
	ordinal_weekday: number | null;
	start_date: string;
	end_mode: 'after' | 'on';
	duration_count: number | null;
	duration_unit: 'day' | 'week' | 'month' | 'year' | null;
	end_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
};

// How many visits a rule makes and where it starts and stops, answered by the server so the number shown
// before saving is the number that gets written.
export type JobRecurrencePreview = {
	visit_count: number;
	first_date: string | null;
	last_date: string | null;
	end_date: string;
	limit: number;
	over_limit: boolean;
};

export const jobRecurrencePreviewKey = (rule: JobRecurrenceInput) =>
	['jobs', 'recurrence-preview', rule] as const;

export async function previewJobRecurrence(
	recurrence: JobRecurrenceInput
): Promise<JobRecurrencePreview> {
	const response = await fetch('/api/jobs/recurrence-preview', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ recurrence })
	});
	return readOrThrow<JobRecurrencePreview>(response, 'That schedule could not be read.');
}

export type CreateJobPayload = {
	client_id: string;
	property_id: string;
	title: string;
	instructions: string | null;
	invoice_on_close: boolean;
	// One-off work carries its visits; recurring work carries a rule and no visits; as-needed work carries
	// neither. Type is fixed at creation and can never be switched afterwards.
	job_type: JobType;
	is_as_needed: boolean;
	recurrence: JobRecurrenceInput | null;
	lines: JobScopeLineInput[];
	visits: JobVisitInput[];
	// A stable key for one save intent, so a double click or a network retry gets the first job back rather
	// than a second one. The fingerprint travels with it: the same key carrying different details is a
	// conflict, not a replay.
	idempotency_key: string;
	request_hash: string;
};

export type CreateJobResult = {
	applied: boolean;
	job_id: string;
	job_number: number;
	job_type: JobType;
	is_as_needed: boolean;
	visit_count: number;
	line_count: number;
	total_minor: number;
};

export async function createJob(payload: CreateJobPayload): Promise<CreateJobResult> {
	const response = await fetch('/api/jobs', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload)
	});
	return readOrThrow<CreateJobResult>(response, 'That job could not be saved.');
}

// --- Reading one job --------------------------------------------------------------------------------------

// A job's own copy of one line of work, exactly as the database stores it. Prices are null for a reader
// without jobs.view_price and for the text/heading lines that carry no price at all.
export type JobLineItem = {
	id: string;
	position: number;
	source_catalog_item_id: string | null;
	line_kind: 'priced' | 'text' | 'heading';
	category: 'product' | 'service' | null;
	is_labor: boolean;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number | null;
	unit_price_minor: number | null;
	unit_cost_minor: number | null;
	is_taxable: boolean;
	image_attachment_id: string | null;
	line_total_minor: number | null;
	line_cost_total_minor: number | null;
};

// One appointment as read back. The three schedule shapes are read off the date and start time, never
// stored: no date is unscheduled, a date with no start time is anytime, a date with a start time is booked.
export type JobVisit = {
	id: string;
	position: number;
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	title: string | null;
	instructions: string | null;
	completed_at: string | null;
	// The visit's own optimistic-lock token. An edit or a delete sends the revision it last read; a bump in
	// between is refused so two dispatchers cannot silently overwrite each other.
	revision: number;
	assignee_ids: string[];
};

// The job's money, gated. Null for a reader without jobs.view_price at all; cost and profit are null on top
// of that for a reader without jobs.view_cost.
export type JobMoney = {
	subtotal_minor: number;
	discount_minor: number;
	discount_name: string | null;
	discount_type: 'fixed' | 'percentage' | null;
	discount_value: number | null;
	tax_minor: number;
	tax_name: string | null;
	// Which of the five tax options the job is on. 'no_tax' and 'not_configured' both come to nothing, but
	// only one of them is a decision somebody made, so the card has to be able to tell them apart.
	tax_source: string;
	tax_rate_id: string | null;
	tax_rate_basis_points: number;
	total_minor: number;
	cost_minor: number | null;
	profit_minor: number | null;
};

// One open invoice reminder — an internal to-do for our own team, never a message to the client. The kind
// says where it came from: a month-end reminder seeds itself from the billing choice and can only be
// dismissed, while a custom-date one a person typed can also be deleted outright. per_visit and
// on_completion exist in the database but are not raised until Part 13 wires the visit and close events.
export type JobInvoiceReminder = {
	id: string;
	reminder_kind: 'on_completion' | 'per_visit' | 'monthly_last_day' | 'custom_date';
	due_on: string;
	note: string | null;
};

export type JobDetail = {
	// The job's repeat rule, present only for a recurring job that has one. "Edit all visits" opens on this.
	recurrence: JobRecurrenceInput | null;
	job: {
		id: string;
		job_number: number;
		title: string;
		job_type: JobType;
		is_as_needed: boolean;
		status: 'active' | 'closed';
		derived_status: JobDerivedStatus;
		price_basis: string;
		billing_timing: string;
		currency_code: string;
		instructions: string | null;
		contract_start_date: string | null;
		contract_end_date: string | null;
		created_at: string;
		revision: number;
		from_quote: boolean;
		client: {
			id: string;
			display_name: string | null;
			company_name: string | null;
			email: string | null;
			phone: string | null;
		} | null;
		property: {
			id: string;
			label: string | null;
			address_line1: string | null;
			address_line2: string | null;
			city: string | null;
			state_region: string | null;
			postal_code: string | null;
		} | null;
	};
	lines: JobLineItem[];
	visits: JobVisit[];
	// The job's open invoice reminders, oldest due date first. Resolved ones are history, not here.
	reminders: JobInvoiceReminder[];
	// The organisation's own calendar day (YYYY-MM-DD in its timezone), so the reminders card can tell a
	// reminder that is already due from one still to come using the same clock the derived status does.
	organization_today: string;
	money: JobMoney | null;
	locale: string;
	can_edit: boolean;
	can_schedule: boolean;
	can_see_price: boolean;
	can_see_cost: boolean;
	can_manage_taxes: boolean;
};

export const jobDetailKey = (id: string) => ['jobs', 'detail', id] as const;

export async function fetchJob(id: string): Promise<JobDetail> {
	const response = await fetch(`/api/jobs/${id}`);
	return readOrThrow<JobDetail>(response, 'That job could not be loaded.');
}

// --- A job's history --------------------------------------------------------------------------------------

// One entry in the job's own activity spine (`job_events`), newest first. Metadata is redacted in the
// database — counts, reasons and ids only, never customer content or money a reader may not see.
export type JobEvent = {
	id: string;
	event_type: string;
	actor_name: string | null;
	created_at: string;
	metadata: Record<string, unknown>;
};

export const jobEventsKey = (id: string) => ['jobs', 'events', id] as const;

export async function fetchJobEvents(id: string): Promise<JobEvent[]> {
	const response = await fetch(`/api/jobs/${id}/events`);
	return readOrThrow<{ events: JobEvent[] }>(response, 'That history could not be loaded.').then(
		(body) => body.events
	);
}

// --- Editing a job's details ------------------------------------------------------------------------------

export type SaveJobDetailsResult = { revision: number };

export async function saveJobDetails(
	id: string,
	expectedRevision: number,
	details: { title: string; instructions: string | null }
): Promise<SaveJobDetailsResult> {
	const response = await fetch(`/api/jobs/${id}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...details })
	});
	return readOrThrow<SaveJobDetailsResult>(response, 'Those changes could not be saved.');
}

// --- Pricing and billing a job (Part 11a) -----------------------------------------------------------------

// Every one of these four saves guards on the revision the browser last read and hands back the next one.
// None of them returns money: the page reloads the job for that, so the amounts stay behind the database's
// own jobs.view_price gate rather than being echoed back by a write.
export type JobRevisionResult = { revision: number };

export async function saveJobLines(
	id: string,
	expectedRevision: number,
	lines: JobScopeLineInput[]
): Promise<JobRevisionResult & { line_count: number }> {
	const response = await fetch(`/api/jobs/${id}/lines`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, lines })
	});
	return readOrThrow(response, 'That scope could not be saved.');
}

export type JobBillingInput = { price_basis: string; billing_timing: string };

export async function saveJobBilling(
	id: string,
	expectedRevision: number,
	billing: JobBillingInput
): Promise<JobRevisionResult> {
	const response = await fetch(`/api/jobs/${id}/billing`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...billing })
	});
	return readOrThrow(response, 'That billing setup could not be saved.');
}

// A null type removes the discount, which is why every field but the revision is optional.
export type JobDiscountInput = {
	type: 'fixed' | 'percentage' | null;
	name: string | null;
	value: number | null;
};

export async function saveJobDiscount(
	id: string,
	expectedRevision: number,
	discount: JobDiscountInput
): Promise<JobRevisionResult> {
	const response = await fetch(`/api/jobs/${id}/discount`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...discount })
	});
	return readOrThrow(response, 'That discount could not be saved.');
}

export type JobTaxInput = {
	source: string;
	rate_id?: string | null;
	custom_name?: string | null;
	custom_rate_basis_points?: number | null;
	save_as_reusable?: boolean;
};

export async function saveJobTax(
	id: string,
	expectedRevision: number,
	tax: JobTaxInput
): Promise<JobRevisionResult> {
	const response = await fetch(`/api/jobs/${id}/tax`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...tax })
	});
	return readOrThrow(response, 'That tax could not be saved.');
}

// --- Invoice reminders (Part 11b) -------------------------------------------------------------------------

// Add a custom-date reminder. Re-adding the same open date is a no-op that returns the reminder already
// there, so the caller reloads the job either way and never has to reason about the duplicate.
export async function addJobReminder(
	jobId: string,
	dueOn: string,
	note: string | null
): Promise<{ id: string }> {
	const response = await fetch(`/api/jobs/${jobId}/reminders`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ due_on: dueOn, note })
	});
	return readOrThrow<{ id: string }>(response, 'That reminder could not be added.');
}

// Mark a reminder handled, keeping the row as history. A month-end reminder rolls forward to next month;
// the database does that inside the command.
export async function dismissJobReminder(
	jobId: string,
	reminderId: string
): Promise<{ id: string; status: string }> {
	const response = await fetch(`/api/jobs/${jobId}/reminders/${reminderId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' }
	});
	return readOrThrow(response, 'That reminder could not be dismissed.');
}

// Delete a mistaken custom-date reminder outright. Only custom dates can be deleted; the command refuses
// any other kind, which the browser never offers anyway.
export async function deleteJobReminder(
	jobId: string,
	reminderId: string
): Promise<{ id: string; deleted: boolean }> {
	const response = await fetch(`/api/jobs/${jobId}/reminders/${reminderId}`, {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' }
	});
	return readOrThrow(response, 'That reminder could not be deleted.');
}

// --- Scheduling a job's visits (Part 9) -------------------------------------------------------------------

// One visit as an add-visits action describes it. Unlike the create form's input it carries no position — the
// command appends new visits after the job's existing ones — and it names where the visit came from so a
// duplicate or a return trip reads truthfully in the history.
export type AddVisitInput = {
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	title: string | null;
	instructions: string | null;
	assignee_ids: string[];
	source?: 'manual' | 'return' | 'duplicated';
};

export type AddJobVisitsResult = { applied: boolean; added_count: number; visit_ids: string[] };

export async function addJobVisits(
	jobId: string,
	visits: AddVisitInput[],
	idempotencyKey: string,
	requestHash: string
): Promise<AddJobVisitsResult> {
	const response = await fetch(`/api/jobs/${jobId}/visits`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			visits,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	return readOrThrow<AddJobVisitsResult>(response, 'Those visits could not be added.');
}

// The whole desired state of one visit. The assignee set replaces the visit's crew exactly; an empty array
// clears it.
export type UpdateVisitInput = {
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	title: string | null;
	instructions: string | null;
	assignee_ids: string[];
};

export type UpdateJobVisitResult = { revision: number };

export async function updateJobVisit(
	jobId: string,
	visitId: string,
	expectedRevision: number,
	visit: UpdateVisitInput
): Promise<UpdateJobVisitResult> {
	const response = await fetch(`/api/jobs/${jobId}/visits/${visitId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision, ...visit })
	});
	return readOrThrow<UpdateJobVisitResult>(response, 'That visit could not be saved.');
}

export async function deleteJobVisit(
	jobId: string,
	visitId: string,
	expectedRevision: number
): Promise<{ applied: boolean }> {
	const response = await fetch(`/api/jobs/${jobId}/visits/${visitId}`, {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ expected_revision: expectedRevision })
	});
	return readOrThrow<{ applied: boolean }>(response, 'That visit could not be removed.');
}

export type MoveJobVisitsResult = { applied: boolean; moved_count: number };

export async function moveJobVisits(
	jobId: string,
	visitIds: string[],
	dayOffset: number,
	idempotencyKey: string,
	requestHash: string
): Promise<MoveJobVisitsResult> {
	const response = await fetch(`/api/jobs/${jobId}/visits/bulk-move`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			visit_ids: visitIds,
			day_offset: dayOffset,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	return readOrThrow<MoveJobVisitsResult>(response, 'Those visits could not be moved.');
}

// --- Editing a recurring job's schedule ------------------------------------------------------------------

export type RescheduleJobVisitsResult = {
	applied: boolean;
	removed_count: number;
	created_count: number;
	completed_kept: number;
	first_date: string | null;
	last_date: string | null;
	revision: number;
};

// "Edit all visits". Replaces the repeat rule and rebuilds every incomplete visit from it, keeping completed
// ones. The counts come back so the toast can say what actually happened rather than guessing.
export async function rescheduleJobVisits(
	jobId: string,
	expectedRevision: number,
	recurrence: JobRecurrenceInput,
	idempotencyKey: string,
	requestHash: string
): Promise<RescheduleJobVisitsResult> {
	const response = await fetch(`/api/jobs/${jobId}/schedule`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			expected_revision: expectedRevision,
			recurrence,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	return readOrThrow<RescheduleJobVisitsResult>(response, 'That schedule could not be saved.');
}

export type ApplyVisitToFutureResult = { applied: boolean; updated_count: number };

// "Save and update future visits". Copies this visit's time of day and/or crew onto the job's later
// incomplete visits; completed and undated ones are skipped by the command itself.
export async function applyVisitToFuture(
	jobId: string,
	visitId: string,
	fields: { time_of_day: boolean; assigned_team: boolean },
	idempotencyKey: string,
	requestHash: string
): Promise<ApplyVisitToFutureResult> {
	const response = await fetch(`/api/jobs/${jobId}/visits/${visitId}/apply-to-future`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			...fields,
			idempotency_key: idempotencyKey,
			request_hash: requestHash
		})
	});
	return readOrThrow<ApplyVisitToFutureResult>(
		response,
		'Those settings could not be applied to the later visits.'
	);
}
