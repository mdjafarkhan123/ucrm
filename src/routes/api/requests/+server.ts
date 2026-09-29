import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { requestSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	DISPLAY_REQUEST_STATUSES,
	deriveRequestStatus,
	displayStatusFilter,
	organizationDayRange,
	type DisplayRequestStatus
} from '$lib/server/requests/status';
import { organizationTimezone } from '$lib/server/requests/timezone';
import { embeddedOne } from '$lib/server/api/embedded';
import { clientNameSearchBranch } from '$lib/server/api/client-name-search';

export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = requestSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = auth.organization.id;
	const [{ data: client }, { data: property }] = await Promise.all([
		event.locals.supabase
			.from('clients')
			.select('id')
			.eq('id', parsed.data.client_id)
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.maybeSingle(),
		event.locals.supabase
			.from('properties')
			.select('id')
			.eq('id', parsed.data.property_id)
			.eq('client_id', parsed.data.client_id)
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.maybeSingle()
	]);

	if (!client) return validationError({ client_id: 'Choose a client in your organization.' });
	if (!property)
		return validationError({ property_id: 'Choose a property belonging to this client.' });

	const { data, error } = await event.locals.supabase
		.from('requests')
		.insert({ organization_id: organizationId, ...parsed.data })
		.select()
		.single();

	if (error) return databaseError();
	return json({ request: data }, { status: 201, headers: NO_STORE_HEADERS });
};

const PAGE_SIZE_DEFAULT = 25;
const PAGE_SIZE_MAX = 50;

// The click-to-sort columns on the list header. Each maps to the raw column its own index is built on
// (`requests_organization_created_idx`, `requests_organization_title_idx`) — never interpolate the `sort`
// param straight into a query.
const REQUEST_SORT_COLUMNS = {
	requested: 'created_at',
	title: 'title'
} as const;
type RequestSortKey = keyof typeof REQUEST_SORT_COLUMNS;

function readSort(params: URLSearchParams) {
	const key = params.get('sort');
	const sort: RequestSortKey = key === 'title' ? key : 'requested';
	const ascending = params.get('dir') === 'asc';
	return { sort, column: REQUEST_SORT_COLUMNS[sort], ascending };
}

// Keyset pagination, never offset, and id breaks ties so a row tied with another on the sort column
// cannot be skipped or shown twice. Cursor format: "<sort column's value>|<id>".
function readCursor(raw: string | null) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const value = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (id.length === 0) return null;
	return { value, id };
}

// PostgREST's or= filter string treats comma/parenthesis as syntax, and a request's title can contain
// either — quoting (and escaping backslash/quote inside it) keeps a cursor value from being parsed as
// extra filter clauses.
function quoteFilterValue(value: string) {
	return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;
	const params = event.url.searchParams;

	const search = params.get('search')?.trim() ?? '';
	const statuses = params
		.getAll('status')
		.flatMap((value) => value.split(','))
		.map((value) => value.trim())
		.filter((value): value is DisplayRequestStatus =>
			(DISPLAY_REQUEST_STATUSES as readonly string[]).includes(value)
		);
	const limit = Math.min(
		PAGE_SIZE_MAX,
		Math.max(
			1,
			Number.parseInt(params.get('limit') ?? String(PAGE_SIZE_DEFAULT), 10) || PAGE_SIZE_DEFAULT
		)
	);
	const cursor = readCursor(params.get('cursor'));
	const { column: sortColumn, ascending } = readSort(params);
	// Narrows to one client's requests, e.g. the client page's Work overview. Unset on the ordinary list.
	const clientIdParam = params.get('client_id');
	const clientId = clientIdParam === null ? null : z.string().uuid().safeParse(clientIdParam);
	if (clientId && !clientId.success) {
		return validationError({ client_id: 'Choose a client in your organization.' });
	}

	// The contractor's timezone is needed twice — for the filter's day boundaries and for each row's
	// badge — so it is read once, up front.
	const timezone = await organizationTimezone(organizationId);
	const now = new Date();

	// Read from `request_list_rows` (the request with its assessment on the same row) so the Status
	// filter can match the badge the office sees, calendar statuses included.
	let query = supabase
		.from('request_list_rows')
		.select(
			`id, title, status, service_type, created_at, client_id,
			 assessment_id, assessment_starts_at, assessment_ends_at, assessment_all_day, assessment_completed_at,
			 client:clients!requests_client_organization_fk(id, display_name, company_name),
			 property:properties!requests_property_organization_fk(id, label, address_line1, city, state_region, postal_code)`
		)
		.eq('organization_id', organizationId);
	if (clientId) query = query.eq('client_id', clientId.data);

	const statusFilter = displayStatusFilter(statuses, organizationDayRange(timezone, now));
	if (statusFilter) query = query.or(statusFilter);
	let searchNarrowed = false;
	if (search) {
		// PostgREST parses commas and parentheses inside or= as syntax, so the term is quoted and its
		// backslashes, quotes, and ilike wildcards escaped before it goes in.
		const escaped = search.replace(/[%_]/g, (match) => `\\${match}`);
		const quoted = `"%${escaped.replace(/"/g, '\\"')}%"`;

		// A request has no name of its own, so the client's name is matched too (see clientNameSearchBranch).
		const clientSearch = await clientNameSearchBranch(supabase, organizationId, quoted);
		if (!clientSearch.ok) return databaseError();
		searchNarrowed = clientSearch.narrowed;
		query = query.or(`title.ilike.${quoted},service_type.ilike.${quoted}${clientSearch.branch}`);
	}
	if (cursor) {
		// The seek (gte/lte) is what the index actually scans on, so the query starts at the cursor row
		// instead of walking the whole list from the top; the `or` then drops the cursor row itself and
		// anything tied with it on the wrong side of id. Verified with EXPLAIN for the default (created_at)
		// sort — the index condition covers organization_id and the sort column, ordering comes free.
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

	// One extra row tells us whether another page exists without a second count query.
	const { data: rows, error } = await query
		.order(sortColumn, { ascending })
		.order('id', { ascending })
		.limit(limit + 1);
	if (error) return databaseError();

	const page = (rows ?? []).slice(0, limit);
	const hasMore = (rows ?? []).length > limit;

	// The one lookup that cannot be embedded: contact methods hang off the client, not the request.
	// Fetched once for the whole page, so the list stays two round trips whatever the page size.
	const clientIds = [
		...new Set(page.map((row) => row.client_id).filter((id): id is string => id !== null))
	];
	const { data: contactMethods, error: contactMethodsError } =
		clientIds.length > 0
			? await supabase
					.from('client_contact_methods')
					.select('client_id, kind, value')
					.eq('organization_id', organizationId)
					.eq('is_primary', true)
					.in('client_id', clientIds)
			: { data: [], error: null };
	if (contactMethodsError) return databaseError();

	const contactByClient = new Map<string, { email: string | null; phone: string | null }>();
	for (const method of contactMethods ?? []) {
		const entry = contactByClient.get(method.client_id) ?? { email: null, phone: null };
		if (method.kind === 'email') entry.email = method.value;
		if (method.kind === 'phone') entry.phone = method.value;
		contactByClient.set(method.client_id, entry);
	}

	const requests = page.map((row) => {
		const assessment = row.assessment_id
			? {
					id: row.assessment_id,
					starts_at: row.assessment_starts_at,
					ends_at: row.assessment_ends_at,
					all_day: row.assessment_all_day ?? false,
					completed_at: row.assessment_completed_at
				}
			: null;
		const contact = row.client_id ? contactByClient.get(row.client_id) : undefined;
		return {
			id: row.id,
			title: row.title,
			service_type: row.service_type,
			requested_at: row.created_at,
			stored_status: row.status,
			status: deriveRequestStatus(row.status ?? 'new', assessment, timezone, now),
			client: embeddedOne(row.client),
			property: embeddedOne(row.property),
			assessment,
			email: contact?.email ?? null,
			phone: contact?.phone ?? null
		};
	});

	const last = page.at(-1) as Record<string, unknown> | undefined;
	const nextCursor = hasMore && last ? `${last[sortColumn]}|${last.id}` : null;
	return json(
		{ requests, next_cursor: nextCursor, search_narrowed: searchNarrowed },
		{ headers: PRIVATE_READ_HEADERS }
	);
};
