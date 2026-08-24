import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	createQuoteSchema,
	quoteListQuerySchema,
	STORED_QUOTE_STATUSES,
	type StoredQuoteStatus
} from '$lib/server/validation/quotes.schema';
import { quoteWriteError } from '$lib/server/quotes/errors';
import { embeddedOne } from '$lib/server/api/embedded';
import { organizationFormatting } from '$lib/server/requests/timezone';

// Starting a quote from nothing. Everything that makes it a quote — the number, the draft version, the
// address snapshot, the pipeline card — happens inside one database command, so a half-made quote with a
// number and no draft cannot exist.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.create');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = createQuoteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('create_quote', {
		target_client_id: parsed.data.client_id,
		target_property_id: parsed.data.property_id,
		quote_title: parsed.data.title,
		disclaimer: parsed.data.contract_disclaimer
	});

	if (error) return quoteWriteError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};

// Archived quotes are out of the way, not deleted. They come back only when somebody asks for them by
// name in the status filter.
const DEFAULT_STATUSES = STORED_QUOTE_STATUSES.filter((status) => status !== 'archived');

const SORT_COLUMNS = { created: 'created_at', number: 'quote_number' } as const;

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

// PostgREST's or= filter treats comma and parenthesis as syntax, and a quote title can contain either.
function quoteFilterValue(value: string) {
	return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'quotes.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const canSeePrice = hasPermission(check.access, 'quotes.view_price');

	const parsed = quoteListQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { search, sort, dir, created_from, created_to, limit } = parsed.data;
	const ascending = dir === 'asc';
	const sortColumn = SORT_COLUMNS[sort];
	const cursor = readCursor(parsed.data.cursor);

	const requested = (parsed.data.status ?? '')
		.split(',')
		.map((value) => value.trim())
		.filter((value): value is StoredQuoteStatus =>
			(STORED_QUOTE_STATUSES as readonly string[]).includes(value)
		);
	const statuses = requested.length > 0 ? requested : DEFAULT_STATUSES;

	// The total lives on the version a quote is currently working from: the draft while one is open, and the
	// published snapshot once the draft has been frozen away. Both pointers come back embedded rather than as
	// a second round trip per row.
	let query = supabase
		.from('quotes')
		.select(
			`id, quote_number, title, status, currency_code, created_at, client_id, request_id,
			 client:clients!quotes_client_organization_fk(id, display_name, company_name),
			 property:properties!quotes_property_organization_fk(id, label, address_line1, city, state_region, postal_code),
			 draft:quote_versions!quotes_draft_version_organization_fk(id${canSeePrice ? ', total_minor' : ''}),
			 published:quote_versions!quotes_current_published_version_fk(id${canSeePrice ? ', total_minor' : ''})`
		)
		.eq('organization_id', organizationId)
		.in('status', statuses);

	if (created_from) query = query.gte('created_at', created_from);
	if (created_to) query = query.lte('created_at', created_to);

	if (search) {
		const escaped = search.replace(/[\%_]/g, (match) => `\\${match}`);
		const quoted = `"%${escaped.replace(/"/g, '\\"')}%"`;
		// A person searching a list of quotes types either a name or a number, so both are tried. A
		// non-numeric term never reaches the integer column.
		const asNumber = Number.parseInt(search, 10);
		query = Number.isSafeInteger(asNumber)
			? query.or(`title.ilike.${quoted},quote_number.eq.${asNumber}`)
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
	// formatting rides along so the Total column writes money the same way the pricing block does; that
	// lookup is one cached row per tenant, not a second trip per list.
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

	const quotes = page.map((row) => {
		const version = (embeddedOne(row.draft) ?? embeddedOne(row.published)) as {
			total_minor?: number;
		} | null;
		return {
			id: row.id,
			quote_number: row.quote_number,
			title: row.title,
			status: row.status,
			currency_code: row.currency_code,
			created_at: row.created_at,
			from_request: row.request_id !== null,
			client: embeddedOne(row.client),
			property: embeddedOne(row.property),
			// Withheld rather than zeroed: a person who may not see money gets no number at all, and the
			// table shows a dash instead of a wrong total.
			// The column says Total, so it is the total: what the client would pay after any discount and
			// tax, not the subtotal the lines add up to.
			total_minor: canSeePrice ? (version?.total_minor ?? 0) : null
		};
	});

	const last = page.at(-1) as Record<string, unknown> | undefined;
	const nextCursor = hasMore && last ? `${last[sortColumn]}|${last.id}` : null;
	return json(
		{
			quotes,
			next_cursor: nextCursor,
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
