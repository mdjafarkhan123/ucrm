import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { readyToBillQuerySchema } from '$lib/server/validation/invoices.schema';
import { organizationFormatting } from '$lib/server/requests/timezone';

// The ready-to-bill queue: every job that owes an invoice today, oldest first, across every client.
//
// The read is `public.ready_to_bill_page`, which checks invoices.create and jobs.view_price for itself and
// scopes every row to the one organization. It returns the amount still waiting on each job, so this route
// never assembles money of its own — a member without job prices is refused by the function rather than
// handed a list of blanks.
type ReadyToBillRow = {
	job_id: string;
	job_number: number;
	title: string;
	job_type: string;
	price_basis: string;
	billing_timing: string;
	currency_code: string;
	oldest_due_on: string;
	cursor_reminder: string;
	due_reminder_count: number;
	unit_kind: string;
	unit_count: number;
	uninvoiced_minor: number;
	client_id: string | null;
	client_display_name: string | null;
	client_company_name: string | null;
	property_label: string | null;
	property_address_line1: string | null;
	property_city: string | null;
};

// Cursor format: "<oldest due date>|<reminder id>". The reminder id breaks the tie between two jobs that have
// owed an invoice since the same day, so neither can be skipped or shown twice.
function readCursor(raw: string | undefined) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const dueOn = raw.slice(0, separator);
	const reminderId = raw.slice(separator + 1);
	return reminderId.length === 0 ? null : { dueOn, reminderId };
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	const parsed = readyToBillQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { search, limit } = parsed.data;
	const cursor = readCursor(parsed.data.cursor);

	// Somebody looking for waiting work types a client's name or a job's title or number, so all three are
	// tried. A non-numeric term never reaches the integer column.
	const asNumber = search ? Number.parseInt(search, 10) : NaN;
	const searchNumber = Number.isSafeInteger(asNumber) ? asNumber : null;
	const searchLike = search ? `%${search.replace(/[%_]/g, (match) => `\\${match}`)}%` : null;

	// One extra row tells us whether another page exists without a second count query.
	const [{ data: rows, error }, formatting] = await Promise.all([
		supabase.rpc('ready_to_bill_page', {
			target_organization_id: organizationId,
			search_like: searchLike,
			search_number: searchNumber,
			cursor_due_on: cursor?.dueOn ?? null,
			cursor_reminder_id: cursor?.reminderId ?? null,
			page_limit: limit + 1
		}),
		organizationFormatting(supabase, organizationId)
	]);
	if (error) return databaseError();

	const allRows = (rows ?? []) as ReadyToBillRow[];
	const page = allRows.slice(0, limit);
	const hasMore = allRows.length > limit;
	const last = page.at(-1);

	return json(
		{
			jobs: page.map((row) => ({
				job_id: row.job_id,
				job_number: row.job_number,
				title: row.title,
				job_type: row.job_type,
				price_basis: row.price_basis,
				billing_timing: row.billing_timing,
				currency_code: row.currency_code,
				oldest_due_on: row.oldest_due_on,
				due_reminder_count: row.due_reminder_count,
				unit_kind: row.unit_kind,
				unit_count: row.unit_count,
				uninvoiced_minor: row.uninvoiced_minor,
				client: row.client_id
					? {
							id: row.client_id,
							display_name: row.client_display_name,
							company_name: row.client_company_name
						}
					: null,
				property: {
					label: row.property_label,
					address_line1: row.property_address_line1,
					city: row.property_city
				}
			})),
			next_cursor: hasMore && last ? `${last.oldest_due_on}|${last.cursor_reminder}` : null,
			timezone: formatting.formatting?.timezone ?? 'UTC',
			locale: formatting.formatting?.locale ?? 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
