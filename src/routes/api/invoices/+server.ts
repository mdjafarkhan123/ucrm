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
	createInvoiceSchema,
	invoiceListQuerySchema,
	readInvoiceStatusFilter
} from '$lib/server/validation/invoices.schema';
import { requireOrganization } from '$lib/server/auth/organization';
import { createInvoiceError } from '$lib/server/invoices/errors';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { asMoneyMap } from '$lib/server/quotes/money';

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

type InvoicePageRow = {
	id: string;
	invoice_number: number;
	subject: string;
	currency_code: string;
	issue_date: string;
	due_date: string;
	issued_at: string | null;
	created_at: string;
	is_replaced: boolean;
	derived_status: string;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
};

// The Invoices list. It reads public.invoice_list_page, the definer read that carries the client context and
// the derived contract status — Draft, Awaiting payment, Past due, Paid, Bad debt, Voided — worked out once
// in the database. The status needs money the reader may not see, so it is produced behind the function
// boundary and only the label ever comes back; amounts arrive separately through invoice_money, which checks
// invoices.view_price for itself.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const canSeePrice = hasPermission(check.access, 'invoices.view_price');

	const parsed = invoiceListQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { search, sort, dir, created_from, created_to, limit } = parsed.data;
	const cursor = readCursor(parsed.data.cursor);
	const statuses = readInvoiceStatusFilter(parsed.data.status);

	// A person searching a list of bills types either a subject or a number, so both are tried. A non-numeric
	// term never reaches the integer column.
	const asNumber = search ? Number.parseInt(search, 10) : NaN;
	const searchNumber = Number.isSafeInteger(asNumber) ? asNumber : null;
	const searchLike = search ? `%${search.replace(/[%_]/g, (match) => `\\${match}`)}%` : null;

	// The cursor's value is the created_at instant on a created sort and the invoice number on a number sort;
	// only the one that matches the sort is sent, the other stays null.
	const cursorCreated = cursor && sort === 'created' ? cursor.value : null;
	const cursorNumber =
		cursor && sort === 'number' ? Number.parseInt(cursor.value, 10) || null : null;

	// One extra row tells us whether another page exists without a second count query. The organization's
	// formatting rides along so the money columns write figures the same way the invoice does; that lookup is
	// one cached row per tenant, not a second trip per list.
	const [{ data: rows, error }, formatting] = await Promise.all([
		supabase.rpc('invoice_list_page', {
			target_organization_id: organizationId,
			search_like: searchLike,
			search_number: searchNumber,
			status_filter: statuses.length > 0 ? statuses : null,
			sort_key: sort,
			sort_dir: dir,
			created_from: created_from ?? null,
			created_to: created_to ?? null,
			cursor_created: cursorCreated,
			cursor_number: cursorNumber,
			cursor_id: cursor?.id ?? null,
			page_limit: limit + 1
		}),
		organizationFormatting(supabase, organizationId)
	]);
	if (error) return databaseError();

	const allRows = (rows ?? []) as InvoicePageRow[];
	const page = allRows.slice(0, limit);
	const hasMore = allRows.length > limit;

	// Money never leaves the invoice table on its own grant, so the page's totals come back in one gated call
	// that checks invoices.view_price for itself. A reader without it is not asked at all.
	const pageIds = canSeePrice ? page.map((row) => row.id) : [];
	const { data: invoiceMoney, error: moneyError } = pageIds.length
		? await supabase.rpc('invoice_money', { target_invoice_ids: pageIds })
		: { data: {}, error: null };
	if (moneyError) return databaseError();
	const money = asMoneyMap(invoiceMoney);

	const invoices = page.map((row) => {
		const cell = money[row.id];
		const total = cell?.total_minor;
		const remaining = cell?.remaining_minor;
		return {
			id: row.id,
			invoice_number: row.invoice_number,
			subject: row.subject,
			currency_code: row.currency_code,
			issue_date: row.issue_date,
			due_date: row.due_date,
			issued_at: row.issued_at,
			created_at: row.created_at,
			is_replaced: row.is_replaced,
			derived_status: row.derived_status,
			client: row.client_id
				? {
						id: row.client_id,
						display_name: row.client_display_name,
						company_name: row.client_company_name
					}
				: null,
			// Withheld rather than zeroed: a person who may not see money gets no number at all, and the table
			// shows a dash instead of a wrong total.
			total_minor: canSeePrice ? (typeof total === 'number' ? total : 0) : null,
			remaining_minor: canSeePrice ? (typeof remaining === 'number' ? remaining : 0) : null
		};
	});

	const last = page.at(-1);
	const nextCursor =
		hasMore && last
			? `${sort === 'number' ? last.invoice_number : last.created_at}|${last.id}`
			: null;

	return json(
		{
			invoices,
			next_cursor: nextCursor,
			locale: formatting.ok ? formatting.formatting.locale : 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Creating a draft invoice directly, without a Job behind it. The whole thing — the invoice, its snapshots
// and its lines — is written in one transaction by `create_invoice_draft`, so a failure anywhere leaves
// nothing half-made. The command checks `invoices.create` and `invoices.view_price` itself (and answers the
// same way for a client in another organization), so the route only proves membership. A doubled click sends
// the same idempotency key and gets the first invoice back with `applied: false`.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = createInvoiceSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const input = parsed.data;
	// The command reads each line straight off the jsonb, and the keys the schema produces are exactly the
	// ones it reads, so the validated data goes through untouched.
	const shared = {
		target_organization_id: auth.organization.id,
		target_client_id: input.client_id,
		new_subject: input.subject,
		new_lines: input.lines,
		new_service_property_ids: input.service_property_ids,
		new_payment_term_id: input.payment_term_id,
		new_custom_due_date: input.custom_due_date,
		new_issue_date: input.issue_date,
		new_idempotency_key: input.idempotency_key,
		new_request_hash: input.request_hash
	};

	// Billing a job goes through the composed command so the draft and its claims land in one transaction; a
	// direct invoice has no work to claim and keeps the plain one. Both check their own permissions.
	const { data, error } =
		input.sources && input.sources.length > 0
			? await event.locals.supabase.rpc('create_invoice_from_work', {
					...shared,
					new_sources: input.sources
				})
			: await event.locals.supabase.rpc('create_invoice_draft', shared);

	if (error) return createInvoiceError(error);

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
