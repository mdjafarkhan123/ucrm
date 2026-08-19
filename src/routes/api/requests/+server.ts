import { json } from '@sveltejs/kit';
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
	STORED_REQUEST_STATUSES,
	deriveRequestStatus,
	type StoredRequestStatus
} from '$lib/server/requests/status';
import { organizationTimezone } from '$lib/server/requests/timezone';
import { embeddedOne } from '$lib/server/api/embedded';

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
		.filter((value): value is StoredRequestStatus =>
			(STORED_REQUEST_STATUSES as readonly string[]).includes(value)
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

	let query = supabase
		.from('requests')
		.select(
			`id, title, status, service_type, created_at, client_id,
			 client:clients!requests_client_organization_fk(id, display_name, company_name),
			 property:properties!requests_property_organization_fk(id, label, address_line1, city, state_region, postal_code),
			 assessment:assessments(id, starts_at, ends_at, all_day, completed_at)`
		)
		.eq('organization_id', organizationId);

	if (statuses.length > 0) query = query.in('status', statuses);
	if (search) {
		// PostgREST parses commas and parentheses inside or= as syntax, so the term is quoted and its
		// backslashes, quotes, and ilike wildcards escaped before it goes in.
		const escaped = search.replace(/[\%_]/g, (match) => `\${match}`);
		const quoted = `"%${escaped.replace(/"/g, '\\"')}%"`;
		query = query.or(`title.ilike.${quoted},service_type.ilike.${quoted}`);
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
	const clientIds = [...new Set(page.map((row) => row.client_id))];
	const [{ data: contactMethods, error: contactMethodsError }, timezone] = await Promise.all([
		clientIds.length > 0
			? supabase
					.from('client_contact_methods')
					.select('client_id, kind, value')
					.eq('organization_id', organizationId)
					.eq('is_primary', true)
					.in('client_id', clientIds)
			: Promise.resolve({ data: [], error: null }),
		organizationTimezone(supabase, organizationId)
	]);
	if (contactMethodsError) return databaseError();

	const contactByClient = new Map<string, { email: string | null; phone: string | null }>();
	for (const method of contactMethods ?? []) {
		const entry = contactByClient.get(method.client_id) ?? { email: null, phone: null };
		if (method.kind === 'email') entry.email = method.value;
		if (method.kind === 'phone') entry.phone = method.value;
		contactByClient.set(method.client_id, entry);
	}

	const now = new Date();
	const requests = page.map((row) => {
		const assessment = embeddedOne(row.assessment);
		const contact = contactByClient.get(row.client_id);
		return {
			id: row.id,
			title: row.title,
			service_type: row.service_type,
			requested_at: row.created_at,
			stored_status: row.status,
			status: deriveRequestStatus(row.status, assessment, timezone, now),
			client: embeddedOne(row.client),
			property: embeddedOne(row.property),
			assessment,
			email: contact?.email ?? null,
			phone: contact?.phone ?? null
		};
	});

	const last = page.at(-1) as Record<string, unknown> | undefined;
	const nextCursor = hasMore && last ? `${last[sortColumn]}|${last.id}` : null;
	return json({ requests, next_cursor: nextCursor }, { headers: PRIVATE_READ_HEADERS });
};
