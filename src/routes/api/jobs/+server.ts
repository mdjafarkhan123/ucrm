import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	createJobSchema,
	jobListQuerySchema,
	readJobStatusFilter,
	readJobTypeFilter
} from '$lib/server/validation/jobs.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { createJobError } from '$lib/server/jobs/errors';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { asMoneyMap } from '$lib/server/quotes/money';

const SORT_COLUMNS = { created: 'created_at', number: 'job_number' } as const;

// Cursor format: "<sort column's value>|<id>". Id breaks ties so a row tied with another cannot be
// skipped or shown twice.
function readCursor(raw: string | undefined) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const value = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	return id.length === 0 ? null : { value, id };
}

// PostgREST's or= filter treats comma and parenthesis as syntax, and a job title can contain either.
function quoteFilterValue(value: string) {
	return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

// The Jobs list. It reads `job_list_rows`, the security-invoker view that carries the client and property
// context and the derived status — Upcoming, Today, Late, Unscheduled, Action required, Requires
// invoicing, Ending soon, Archived — worked out once in the database. Nothing here re-derives a status,
// so this list and the Overview card above it can never disagree.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const canSeePrice = hasPermission(check.access, 'jobs.view_price');

	const parsed = jobListQuerySchema.safeParse(Object.fromEntries(event.url.searchParams.entries()));
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { search, sort, dir, created_from, created_to, limit } = parsed.data;
	const ascending = dir === 'asc';
	const sortColumn = SORT_COLUMNS[sort];
	const cursor = readCursor(parsed.data.cursor);
	const statuses = readJobStatusFilter(parsed.data.status);
	const types = readJobTypeFilter(parsed.data.type);

	let query = supabase
		.from('job_list_rows')
		.select(
			`id, job_number, title, job_type, is_as_needed, status, derived_status, currency_code,
			 created_at, contract_start_date, contract_end_date, quote_id,
			 client_id, client_display_name, client_company_name,
			 property_id, property_label, property_address_line1, property_city, property_state_region,
			 property_postal_code`
		)
		.eq('organization_id', organizationId);

	// Closed work is out of the way, not deleted. With no status asked for, the list is the open work —
	// which is also the filter that lets the query walk the partial jobs_active_idx.
	if (statuses.length > 0) {
		query = query.in('derived_status', statuses);
	} else {
		query = query.eq('status', 'active');
	}

	if (types.length > 0) query = query.in('job_type', types);
	if (created_from) query = query.gte('created_at', created_from);
	if (created_to) query = query.lte('created_at', created_to);

	if (search) {
		const escaped = search.replace(/[%_]/g, (match) => `\\${match}`);
		const quoted = `"%${escaped.replace(/"/g, '\\"')}%"`;
		// A person searching a list of jobs types either a name or a number, so both are tried. A
		// non-numeric term never reaches the integer column.
		const asNumber = Number.parseInt(search, 10);
		query = Number.isSafeInteger(asNumber)
			? query.or(`title.ilike.${quoted},job_number.eq.${asNumber}`)
			: query.ilike('title', `%${escaped}%`);
	}

	if (cursor) {
		// The seek is what the index actually scans on, so the query starts at the cursor row instead of
		// walking the list from the top; the `or` then drops the cursor row and anything tied with it on
		// the wrong side of id.
		const quotedValue = quoteFilterValue(cursor.value);
		query = ascending
			? query
					.gte(sortColumn, cursor.value)
					.or(
						`${sortColumn}.gt.${quotedValue},and(${sortColumn}.eq.${quotedValue},id.gt.${cursor.id})`
					)
			: query
					.lte(sortColumn, cursor.value)
					.or(
						`${sortColumn}.lt.${quotedValue},and(${sortColumn}.eq.${quotedValue},id.lt.${cursor.id})`
					);
	}

	// One extra row tells us whether another page exists without a second count query. The organization's
	// formatting rides along so the Total column writes money the same way the job does; that lookup is
	// one cached row per tenant, not a second trip per list.
	const [{ data: rows, error }, formatting] = await Promise.all([
		query
			.order(sortColumn, { ascending })
			.order('id', { ascending })
			.limit(limit + 1),
		organizationFormatting(supabase, organizationId)
	]);
	if (error) return databaseError();

	const page = (rows ?? []).slice(0, limit);
	const hasMore = (rows ?? []).length > limit;

	// Money never leaves the table on its own grant, so the page's totals come back in one gated call that
	// checks jobs.view_price for itself. A reader without it is not asked at all.
	const pageIds = canSeePrice
		? page.map((row) => row.id).filter((id): id is string => typeof id === 'string')
		: [];
	const { data: jobMoney, error: moneyError } = pageIds.length
		? await supabase.rpc('job_money', { target_job_ids: pageIds })
		: { data: {}, error: null };
	if (moneyError) return databaseError();
	const money = asMoneyMap(jobMoney);

	const jobs = page.map((row) => {
		const total = row.id ? money[row.id]?.total_minor : undefined;
		return {
			id: row.id,
			job_number: row.job_number,
			title: row.title,
			job_type: row.job_type,
			is_as_needed: row.is_as_needed,
			derived_status: row.derived_status,
			currency_code: row.currency_code,
			created_at: row.created_at,
			contract_end_date: row.contract_end_date,
			from_quote: row.quote_id !== null,
			client: row.client_id
				? {
						id: row.client_id,
						display_name: row.client_display_name,
						company_name: row.client_company_name
					}
				: null,
			property: row.property_id
				? {
						id: row.property_id,
						label: row.property_label,
						address_line1: row.property_address_line1,
						city: row.property_city,
						state_region: row.property_state_region,
						postal_code: row.property_postal_code
					}
				: null,
			// Withheld rather than zeroed: a person who may not see money gets no number at all, and the
			// table shows a dash instead of a wrong total.
			total_minor: canSeePrice ? (typeof total === 'number' ? total : 0) : null
		};
	});

	const last = page.at(-1) as Record<string, unknown> | undefined;
	const nextCursor = hasMore && last ? `${last[sortColumn]}|${last.id}` : null;
	return json(
		{
			jobs,
			next_cursor: nextCursor,
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Creating a one-off job directly, without a quote. The whole thing — the job, its scope, its 1-20 visits
// and each visit's people — is written in one transaction by `create_job_with_visits`, so a failure
// anywhere leaves nothing half-made. The command checks `jobs.create` itself (and answers the same way for
// a client or property in another organization), so the route only proves membership. A doubled click sends
// the same idempotency key and gets the first job back with `applied: false`.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = createJobSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	const { data, error } = await event.locals.supabase.rpc('create_job_with_visits', {
		target_organization_id: auth.organization.id,
		target_client_id: input.client_id,
		target_property_id: input.property_id,
		new_title: input.title,
		new_instructions: input.instructions,
		invoice_on_close: input.invoice_on_close,
		// The command reads each line and visit straight off the jsonb, and the keys the schema produces are
		// exactly the ones it reads, so the validated data goes through untouched.
		scope_lines: input.lines,
		visits: input.visits,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash,
		// One-off, recurring, or as-needed. A recurring job sends its rule instead of visits and the command
		// generates them; an as-needed job sends neither.
		new_job_type: input.job_type,
		new_is_as_needed: input.is_as_needed,
		new_recurrence: input.recurrence
	});

	if (error) return createJobError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
