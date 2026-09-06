import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { deliverableInvoicesQuerySchema } from '$lib/server/validation/invoices.schema';
import { organizationFormatting } from '$lib/server/requests/timezone';

// The Batch Deliver picker's list: every invoice a person may send in a batch -- draft, awaiting payment, or
// past due -- newest first, across every client. Paid, voided, bad debt and replaced bills never appear.
//
// The read is `public.invoice_batch_deliverable_page`, which checks invoices.view for itself and scopes every
// row to the one organization. It reuses the same derived-status label as the Invoices list, and carries the
// three facts the picker needs: the draft's revision (for issuing on send), whether the client has any email
// (to flag "no email" before submit), and when the invoice was last sent (so a previously-sent bill only ever
// goes again on purpose). It carries no money, so a member without invoices.view_price is not blocked here.
type DeliverableRow = {
	id: string;
	invoice_number: number;
	subject: string;
	currency_code: string;
	due_date: string;
	issued_at: string | null;
	created_at: string;
	derived_status: string;
	revision: number;
	client_id: string | null;
	client_display_name: string | null;
	client_company_name: string | null;
	has_email: boolean;
	last_sent_at: string | null;
};

// Cursor format: "<created instant>|<invoice id>". The id breaks the tie between two invoices created at the
// same instant, so neither can be skipped or shown twice.
function readCursor(raw: string | undefined) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const created = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	return id.length === 0 ? null : { created, id };
}

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	const parsed = deliverableInvoicesQuerySchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { limit } = parsed.data;
	const cursor = readCursor(parsed.data.cursor);

	// One extra row tells us whether another page exists without a second count query.
	const [{ data: rows, error }, formatting] = await Promise.all([
		supabase.rpc('invoice_batch_deliverable_page', {
			target_organization_id: organizationId,
			cursor_created: cursor?.created ?? null,
			cursor_id: cursor?.id ?? null,
			page_limit: limit + 1
		}),
		organizationFormatting(supabase, organizationId)
	]);
	if (error) return databaseError();

	const allRows = (rows ?? []) as DeliverableRow[];
	const page = allRows.slice(0, limit);
	const hasMore = allRows.length > limit;
	const last = page.at(-1);

	return json(
		{
			invoices: page.map((row) => ({
				id: row.id,
				invoice_number: row.invoice_number,
				subject: row.subject,
				currency_code: row.currency_code,
				due_date: row.due_date,
				issued_at: row.issued_at,
				derived_status: row.derived_status,
				revision: row.revision,
				has_email: row.has_email,
				last_sent_at: row.last_sent_at,
				client: row.client_id
					? {
							id: row.client_id,
							display_name: row.client_display_name,
							company_name: row.client_company_name
						}
					: null
			})),
			next_cursor: hasMore && last ? `${last.created_at}|${last.id}` : null,
			timezone: formatting.formatting?.timezone ?? 'UTC',
			locale: formatting.formatting?.locale ?? 'en-US'
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
