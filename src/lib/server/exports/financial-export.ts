// Financial reconciliation, Part 3: the accountant-ready package.
//
// One zip, one CSV per money ledger, a reconciliation summary and a manifest -- the shape QuickBooks Online's
// "Export data" and Stripe's itemized/summary report pairs use, and the shape our own client-book export
// already established. Every row comes from the Part 2 financial readers (`financial_*_page` /
// `financial_*_summary`), so the package can never disagree with the on-screen reports: it is the same
// calculation, paged through to the end.
//
// Streamed, not buffered. Each ledger is read 500 rows at a time by keyset cursor and deflated straight into
// the zip as it arrives, so peak memory is one page plus the compressor and the download starts at once. The
// route caps the range at one year; a longer history is two downloads. No queue, no stored object.
//
// Money is written in major units with exactly two decimals plus an ISO `currency_code` on every row;
// integers in, strings out, no floating point. Dates stay the stored business dates. Internal user ids are
// left out; people appear by name where the reader already names them.
//
// Permissions are the readers' own: a ledger the caller may not read is left out of the zip and named in the
// manifest as omitted, and cost/value columns the caller may not see are dropped from the file -- never
// written as zero. The database rechecks every permission and tenant scope inside each function.

import type { SupabaseClient } from '@supabase/supabase-js';
import Papa from 'papaparse';
import { Zip, ZipDeflate, strToU8 } from 'fflate';
import type { EffectiveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';

// Bumped only when a file's columns or the manifest shape change, so an accountant's import mapping can tell
// the versions apart.
export const FINANCIAL_EXPORT_SCHEMA_VERSION = 2;

// The readers clamp at 501; 500 keeps each round trip one ordered index range.
const PAGE_SIZE = 500;

type Row = Record<string, unknown>;

export type FinancialExportContext = {
	organizationId: string;
	from: string;
	to: string;
	timezone: string;
	currencyCode: string;
	// Balances are a current snapshot; this is the day they are aged from.
	agingAsOf: string;
	generatedAt: Date;
};

// How one ledger is read and written. `page` names the reader and how a page continues from its last row;
// `columns` is the written order, with `*_minor` sources renamed and formatted as major units.
type Ledger = {
	file: string;
	description: string;
	primaryKey: string;
	links?: { column: string; references: string }[];
	allowed: (access: EffectiveOrganizationAccess) => boolean;
	// Columns dropped when the caller lacks this permission (cost or value visibility).
	restricted?: { permission: string; columns: readonly string[] };
	page: {
		fn: string;
		args: (context: FinancialExportContext) => Record<string, unknown>;
		cursor: (last: Row) => Record<string, unknown>;
	};
	summary?: { fn: string; args: (context: FinancialExportContext) => Record<string, unknown> };
	filter?: (row: Row) => boolean;
	// An extra running total the agreement checks need beyond plain column sums (e.g. Won value only).
	tally?: (row: Row, totals: Record<string, bigint>) => void;
	columns: readonly string[];
};

const invoiceVisible = (access: EffectiveOrganizationAccess) =>
	hasPermission(access, 'invoices.view') && hasPermission(access, 'invoices.view_price');
const jobPriceVisible = (access: EffectiveOrganizationAccess) =>
	hasPermission(access, 'jobs.view') && hasPermission(access, 'jobs.view_price');

const range = ({ organizationId, from, to }: FinancialExportContext) => ({
	target_organization_id: organizationId,
	report_from: from,
	report_to: to
});

const PAYMENT_EVENT_COLUMNS = [
	'event_id',
	'event_type',
	'original_event_type',
	'event_date',
	'client_id',
	'client_display_name',
	'client_company_name',
	'amount_minor',
	'cash_effect_minor',
	'currency_code',
	'method',
	'reference',
	'note',
	'original_event_id',
	'original_deposit_event_id',
	'created_at'
] as const;

const paymentEventsPage: Ledger['page'] = {
	fn: 'financial_payment_events_page',
	args: range,
	cursor: (last) => ({ cursor_event_date: last.event_date, cursor_event_id: last.event_id })
};

// Order here is the order in the zip and the manifest.
export const FINANCIAL_LEDGERS: readonly Ledger[] = [
	{
		file: 'invoices_sales.csv',
		description:
			'Billed sales: each issued Invoice, or Draft recognised by full payment, dated by sale_date. Net sales exclude tax. Voided and superseded Invoices are excluded; a write-off keeps the sale and sets written_off_at.',
		primaryKey: 'invoice_id',
		links: [
			{ column: 'root_invoice_id', references: 'invoices_sales.csv:invoice_id' },
			{ column: 'predecessor_invoice_id', references: 'invoices_sales.csv:invoice_id' }
		],
		allowed: invoiceVisible,
		page: {
			fn: 'financial_invoice_sales_page',
			args: range,
			cursor: (last) => ({ cursor_sale_date: last.sale_date, cursor_invoice_id: last.invoice_id })
		},
		summary: { fn: 'financial_invoice_sales_summary', args: range },
		columns: [
			'invoice_id',
			'invoice_number',
			'root_invoice_id',
			'predecessor_invoice_id',
			'client_id',
			'client_display_name',
			'client_company_name',
			'subject',
			'sale_date',
			'recognition_basis',
			'currency_code',
			'net_sales_minor',
			'tax_minor',
			'total_minor',
			'written_off_at',
			'has_unsettled_legacy_closure',
			'created_at'
		]
	},
	{
		file: 'invoice_tax.csv',
		description:
			'Tax per effective Invoice from its frozen tax amount, dated by tax_date. Reported separately from net sales and cash.',
		primaryKey: 'invoice_id',
		links: [{ column: 'invoice_id', references: 'invoices_sales.csv:invoice_id' }],
		allowed: invoiceVisible,
		page: {
			fn: 'financial_invoice_tax_page',
			args: range,
			cursor: (last) => ({ cursor_tax_date: last.tax_date, cursor_invoice_id: last.invoice_id })
		},
		summary: { fn: 'financial_invoice_tax_summary', args: range },
		columns: [
			'invoice_id',
			'invoice_number',
			'client_id',
			'client_display_name',
			'client_company_name',
			'subject',
			'tax_date',
			'recognition_basis',
			'currency_code',
			'tax_source',
			'tax_name',
			'tax_rate_basis_points',
			'net_sales_minor',
			'tax_minor',
			'total_minor',
			'created_at'
		]
	},
	{
		file: 'payment_events.csv',
		description:
			'Cash received: every immutable receipt, refund and reversal on its own date. cash_effect is the signed effect on cash; a reversal removes a mistaken event from corrected totals while both rows remain.',
		primaryKey: 'event_id',
		links: [
			{ column: 'original_event_id', references: 'payment_events.csv:event_id' },
			{ column: 'original_deposit_event_id', references: 'deposits_credits.csv:event_id' }
		],
		allowed: invoiceVisible,
		page: paymentEventsPage,
		summary: { fn: 'financial_payment_events_summary', args: range },
		columns: PAYMENT_EVENT_COLUMNS
	},
	{
		file: 'refunds_reversals.csv',
		description:
			'Corrections only: the refunded and reversed rows of payment_events.csv, each pointing at the original event.',
		primaryKey: 'event_id',
		links: [{ column: 'event_id', references: 'payment_events.csv:event_id' }],
		allowed: invoiceVisible,
		page: paymentEventsPage,
		filter: (row) => row.event_type === 'refunded' || row.event_type === 'reversed',
		columns: PAYMENT_EVENT_COLUMNS
	},
	{
		file: 'payment_allocations.csv',
		description:
			'Which money paid which Invoice. Applying reduces the Invoice balance; unapplying (moving money) reverses an earlier allocation and changes allocation, not cash received.',
		primaryKey: 'allocation_id',
		links: [
			{ column: 'invoice_id', references: 'invoices_sales.csv:invoice_id' },
			{
				column: 'source_event_id',
				references: 'payment_events.csv:event_id | deposits_credits.csv:event_id'
			},
			{ column: 'reversed_allocation_id', references: 'payment_allocations.csv:allocation_id' }
		],
		allowed: invoiceVisible,
		page: {
			fn: 'financial_payment_allocations_page',
			args: range,
			cursor: (last) => ({
				cursor_created_at: last.created_at,
				cursor_allocation_id: last.allocation_id
			})
		},
		summary: { fn: 'financial_payment_allocations_summary', args: range },
		columns: [
			'allocation_id',
			'entry_type',
			'activity_date',
			'invoice_id',
			'invoice_number',
			'client_id',
			'client_display_name',
			'client_company_name',
			'amount_minor',
			'allocation_effect_minor',
			'currency_code',
			'source_type',
			'source_event_id',
			'reversed_allocation_id',
			'reason',
			'created_at'
		]
	},
	{
		file: 'deposits_credits.csv',
		description:
			'Quote deposits received or reversed, with how much of each has since been refunded, allocated to Invoices, or is still available as customer credit.',
		primaryKey: 'event_id',
		links: [{ column: 'reversed_event_id', references: 'deposits_credits.csv:event_id' }],
		allowed: invoiceVisible,
		page: {
			fn: 'financial_deposit_credits_page',
			args: range,
			cursor: (last) => ({ cursor_created_at: last.created_at, cursor_event_id: last.event_id })
		},
		summary: { fn: 'financial_deposit_credits_summary', args: range },
		columns: [
			'event_id',
			'event_type',
			'activity_date',
			'quote_id',
			'quote_number',
			'quote_version_id',
			'client_id',
			'client_display_name',
			'client_company_name',
			'amount_minor',
			'cash_effect_minor',
			'currency_code',
			'method',
			'reference',
			'note',
			'reversed_event_id',
			'refunded_minor',
			'allocated_minor',
			'available_credit_minor',
			'created_at'
		]
	},
	{
		file: 'client_balances.csv',
		description:
			'Current receivables by Client: a snapshot at generation time, not a historical balance. Outstanding is aged by due date as of aging_as_of; available_credit is unused money; client_balance is outstanding less available credit.',
		primaryKey: 'client_id',
		allowed: invoiceVisible,
		page: {
			fn: 'financial_client_aging_page',
			args: ({ organizationId, agingAsOf }) => ({
				target_organization_id: organizationId,
				report_as_of: agingAsOf
			}),
			cursor: (last) => ({ cursor_sort_name: last.sort_name, cursor_client_id: last.client_id })
		},
		summary: {
			fn: 'financial_client_aging_summary',
			args: ({ organizationId, agingAsOf }) => ({
				target_organization_id: organizationId,
				report_as_of: agingAsOf
			})
		},
		columns: [
			'client_id',
			'client_display_name',
			'client_company_name',
			'currency_code',
			'outstanding_minor',
			'not_due_minor',
			'overdue_1_30_minor',
			'overdue_31_60_minor',
			'overdue_61_90_minor',
			'overdue_91_plus_minor',
			'available_credit_minor',
			'client_balance_minor',
			'open_invoice_count'
		]
	},
	{
		file: 'opening_balances.csv',
		description:
			'Imported opening receivables and credits still in effect: the pre-CRM balances every current report and export folds into Client balance. A correction retires its predecessor, which stays traceable but drops out of this file.',
		primaryKey: 'opening_balance_id',
		links: [
			{ column: 'root_opening_balance_id', references: 'opening_balances.csv:opening_balance_id' },
			{
				column: 'predecessor_opening_balance_id',
				references: 'opening_balances.csv:opening_balance_id'
			}
		],
		allowed: invoiceVisible,
		page: {
			fn: 'financial_opening_balances_page',
			args: ({ organizationId }) => ({ target_organization_id: organizationId }),
			cursor: (last) => ({
				cursor_as_of_date: last.as_of_date,
				cursor_opening_balance_id: last.opening_balance_id
			})
		},
		summary: {
			fn: 'financial_opening_balances_summary',
			args: ({ organizationId }) => ({ target_organization_id: organizationId })
		},
		columns: [
			'opening_balance_id',
			'client_id',
			'client_display_name',
			'client_company_name',
			'currency_code',
			'balance_type',
			'receivable_minor',
			'credit_minor',
			'as_of_date',
			'source_note',
			'root_opening_balance_id',
			'predecessor_opening_balance_id',
			'import_batch_id',
			'created_at'
		]
	},
	{
		file: 'job_profitability.csv',
		description:
			'Operational analysis per Job: revenue is Job total less tax; cost is snapshotted item cost plus rated labor plus expenses. Unrated labor is disclosed, not valued at zero. Not billed sales and not cash.',
		primaryKey: 'job_id',
		allowed: jobPriceVisible,
		restricted: {
			permission: 'jobs.view_cost',
			columns: [
				'item_cost_minor',
				'labor_cost_minor',
				'expense_cost_minor',
				'total_cost_minor',
				'profit_minor',
				'margin_basis_points',
				'labor_minutes',
				'unrated_labor_count',
				'unrated_labor_minutes'
			]
		},
		page: {
			fn: 'financial_job_profitability_page',
			args: range,
			cursor: (last) => ({ cursor_job_number: last.job_number })
		},
		summary: { fn: 'financial_job_profitability_summary', args: range },
		columns: [
			'job_id',
			'job_number',
			'job_title',
			'job_type',
			'price_basis',
			'job_status',
			'closed_on',
			'client_id',
			'client_display_name',
			'client_company_name',
			'currency_code',
			'unit_count',
			'revenue_minor',
			'item_cost_minor',
			'labor_cost_minor',
			'expense_cost_minor',
			'total_cost_minor',
			'profit_minor',
			'margin_basis_points',
			'labor_minutes',
			'unrated_labor_count',
			'unrated_labor_minutes'
		]
	},
	{
		file: 'time_entries.csv',
		description:
			'Labor per recorded time entry, dated by its start in the organization timezone. is_unrated marks hours with no rate on file; their cost is blank, not zero. Rows follow the downloader’s own/team time scope.',
		primaryKey: 'entry_id',
		links: [{ column: 'job_id', references: 'job_profitability.csv:job_id' }],
		allowed: (access) =>
			hasPermission(access, 'jobs.view') &&
			(hasPermission(access, 'time.track_team') || hasPermission(access, 'time.track_own')),
		restricted: {
			permission: 'jobs.view_cost',
			columns: ['cost_per_hour_minor', 'cost_total_minor']
		},
		page: {
			fn: 'financial_time_entries_page',
			args: range,
			cursor: (last) => ({ cursor_started_at: last.started_at, cursor_entry_id: last.entry_id })
		},
		summary: { fn: 'financial_time_entries_summary', args: range },
		columns: [
			'entry_id',
			'started_on',
			'started_at',
			'minutes',
			'user_name',
			'job_id',
			'job_number',
			'job_title',
			'client_id',
			'client_display_name',
			'client_company_name',
			'visit_id',
			'visit_date',
			'currency_code',
			'is_unrated',
			'cost_per_hour_minor',
			'cost_total_minor'
		]
	},
	{
		file: 'expenses.csv',
		description:
			'Each Job expense dated by expense_date. Note: job_profitability.csv counts every expense of a closed one-off Job whatever its date, so the two totals differ by design when a receipt was recorded outside the period.',
		primaryKey: 'expense_id',
		links: [{ column: 'job_id', references: 'job_profitability.csv:job_id' }],
		allowed: (access) =>
			hasPermission(access, 'jobs.view') &&
			hasPermission(access, 'jobs.view_cost') &&
			(hasPermission(access, 'expenses.manage_team') || hasPermission(access, 'expenses.record')),
		page: {
			fn: 'financial_expenses_page',
			args: range,
			cursor: (last) => ({
				cursor_expense_date: last.expense_date,
				cursor_expense_id: last.expense_id
			})
		},
		columns: [
			'expense_id',
			'expense_date',
			'name',
			'description',
			'accounting_code',
			'total_minor',
			'currency_code',
			'job_id',
			'job_number',
			'job_title',
			'client_id',
			'client_display_name',
			'client_company_name',
			'reimburse_to_user_name',
			'created_at'
		]
	},
	{
		file: 'uninvoiced_work.csv',
		description:
			'Completed Visits, due periods and finished Jobs not yet billed. Work to invoice, not revenue.',
		primaryKey: 'unit_id',
		links: [{ column: 'job_id', references: 'job_profitability.csv:job_id' }],
		allowed: jobPriceVisible,
		page: {
			fn: 'financial_uninvoiced_work_page',
			args: range,
			cursor: (last) => ({ cursor_work_date: last.work_date, cursor_unit_id: last.unit_id })
		},
		summary: { fn: 'financial_uninvoiced_work_summary', args: range },
		columns: [
			'unit_kind',
			'unit_id',
			'work_date',
			'job_id',
			'job_number',
			'job_title',
			'price_basis',
			'client_id',
			'client_display_name',
			'client_company_name',
			'currency_code',
			'uninvoiced_minor',
			'visit_id',
			'reminder_id'
		]
	},
	{
		file: 'sales_outcomes.csv',
		description:
			'Pipeline opportunities Won or Lost in the period, and Direct jobs (source_kind direct_job: a job created with no request or quote, counted apart from Won). estimated_value is a sales estimate, never financial revenue.',
		primaryKey: 'opportunity_id',
		allowed: (access) => hasPermission(access, 'pipeline.view'),
		restricted: { permission: 'pipeline.view_value', columns: ['estimated_value_minor'] },
		tally: (row, totals) => {
			// A Direct job row is `won` too, but the summary's won_value is deals only.
			if (
				row.outcome === 'won' &&
				row.source_kind !== 'direct_job' &&
				row.estimated_value_minor != null
			) {
				totals.won_estimated_value =
					(totals.won_estimated_value ?? 0n) + BigInt(String(row.estimated_value_minor));
			}
		},
		page: {
			fn: 'financial_sales_outcomes_page',
			args: range,
			cursor: (last) => ({
				cursor_outcome_at: last.outcome_at,
				cursor_opportunity_id: last.opportunity_id
			})
		},
		summary: { fn: 'financial_sales_outcomes_summary', args: range },
		columns: [
			'opportunity_id',
			'outcome',
			'outcome_on',
			'outcome_at',
			'created_on',
			'source_kind',
			'request_id',
			'quote_id',
			'job_id',
			'quote_number',
			'title',
			'client_id',
			'client_display_name',
			'client_company_name',
			'currency_code',
			'estimated_value_minor',
			'lost_reason'
		]
	}
];

// `net_sales_minor` is written as `net_sales`, holding "12.50". Integer arithmetic only.
export function minorToMajor(value: unknown): string {
	if (value === null || value === undefined || value === '') return '';
	const minor = typeof value === 'bigint' ? value : BigInt(String(value));
	const sign = minor < 0n ? '-' : '';
	const magnitude = minor < 0n ? -minor : minor;
	return `${sign}${magnitude / 100n}.${String(magnitude % 100n).padStart(2, '0')}`;
}

function isMoneyColumn(column: string) {
	return column.endsWith('_minor');
}

export function csvHeaderFor(column: string) {
	return isMoneyColumn(column) ? column.slice(0, -'_minor'.length) : column;
}

// Which columns a caller actually gets for a ledger, after cost/value restrictions.
export function visibleColumns(ledger: Ledger, access: EffectiveOrganizationAccess) {
	if (!ledger.restricted || hasPermission(access, ledger.restricted.permission)) {
		return ledger.columns;
	}
	const hidden = new Set(ledger.restricted.columns);
	return ledger.columns.filter((column) => !hidden.has(column));
}

function projectRow(row: Row, columns: readonly string[]): Row {
	const projected: Row = {};
	for (const column of columns) {
		const value = row[column];
		projected[csvHeaderFor(column)] = isMoneyColumn(column)
			? minorToMajor(value)
			: value === null || value === undefined
				? ''
				: value;
	}
	return projected;
}

// Summaries are presented with the same renaming so a total in the summary and a column in the file share a
// name. Absent (permission-hidden) values stay absent.
export function presentSummary(summary: Row | null | undefined): Row | null {
	if (!summary) return null;
	const presented: Row = {};
	for (const [key, value] of Object.entries(summary)) {
		if (value === null || value === undefined) continue;
		presented[csvHeaderFor(key)] = isMoneyColumn(key) ? minorToMajor(value) : value;
	}
	return presented;
}

export type FinancialExportSink = (chunk: Uint8Array) => Promise<void>;

type LedgerResult = {
	file: string;
	rows: number;
	// Sums of the money columns actually written, for the summary-versus-rows agreement check.
	columnTotals: Record<string, bigint>;
	summary: Row | null;
};

async function callReader(supabase: SupabaseClient, fn: string, args: Record<string, unknown>) {
	const { data, error } = await supabase.rpc(fn, args);
	if (error) throw new Error(`Could not read ${fn} for the accounting export: ${error.message}`);
	return (data ?? []) as Row[];
}

// Stream one ledger: header first, then each page as it arrives. Returns what the manifest and summary need.
async function writeLedger(
	supabase: SupabaseClient,
	zip: Zip,
	ledger: Ledger,
	columns: readonly string[],
	context: FinancialExportContext
): Promise<LedgerResult> {
	const entry = new ZipDeflate(ledger.file, { level: 6 });
	entry.mtime = context.generatedAt;
	zip.add(entry);

	const headers = columns.map(csvHeaderFor);
	const moneyColumns = columns.filter(isMoneyColumn);
	const columnTotals: Record<string, bigint> = {};
	for (const column of moneyColumns) columnTotals[csvHeaderFor(column)] = 0n;

	entry.push(strToU8(Papa.unparse([headers]) + '\r\n'));

	let rows = 0;
	let cursor: Record<string, unknown> = {};
	for (;;) {
		const page = await callReader(supabase, ledger.page.fn, {
			...ledger.page.args(context),
			...cursor,
			page_limit: PAGE_SIZE,
			sort_direction: 'asc'
		});
		const kept = ledger.filter ? page.filter(ledger.filter) : page;
		if (kept.length > 0) {
			for (const row of kept) {
				for (const column of moneyColumns) {
					const value = row[column];
					if (value !== null && value !== undefined) {
						columnTotals[csvHeaderFor(column)] += BigInt(String(value));
					}
				}
				ledger.tally?.(row, columnTotals);
			}
			rows += kept.length;
			const body = Papa.unparse(
				kept.map((row) => projectRow(row, columns)),
				{ columns: headers, header: false }
			);
			entry.push(strToU8(body + '\r\n'));
		}
		const last = page.at(-1);
		if (page.length < PAGE_SIZE || !last) break;
		cursor = ledger.page.cursor(last);
	}
	entry.push(new Uint8Array(0), true);

	const summary = ledger.summary
		? ((await callReader(supabase, ledger.summary.fn, ledger.summary.args(context)))[0] ?? null)
		: null;

	return { file: ledger.file, rows, columnTotals, summary };
}

function addJson(zip: Zip, name: string, value: unknown, generatedAt: Date) {
	const entry = new ZipDeflate(name, { level: 6 });
	entry.mtime = generatedAt;
	zip.add(entry);
	entry.push(strToU8(JSON.stringify(value, null, 2)), true);
}

// The totals an accountant checks first, each named by the file and column it must agree with. Each check
// compares the reader's whole-range summary against the sum of the rows actually written to the file: they
// come from the same SQL, so any disagreement is a defect worth reporting rather than hiding.
const AGREEMENT_CHECKS: { file: string; summaryKey: string; column: string }[] = [
	{ file: 'invoices_sales.csv', summaryKey: 'net_sales', column: 'net_sales' },
	{ file: 'invoices_sales.csv', summaryKey: 'tax', column: 'tax' },
	{ file: 'invoices_sales.csv', summaryKey: 'billed_total', column: 'total' },
	{ file: 'invoice_tax.csv', summaryKey: 'tax', column: 'tax' },
	{ file: 'payment_events.csv', summaryKey: 'cash_effect', column: 'cash_effect' },
	{ file: 'payment_allocations.csv', summaryKey: 'net_allocated', column: 'allocation_effect' },
	{ file: 'deposits_credits.csv', summaryKey: 'cash_effect', column: 'cash_effect' },
	{ file: 'client_balances.csv', summaryKey: 'outstanding', column: 'outstanding' },
	{ file: 'client_balances.csv', summaryKey: 'available_credit', column: 'available_credit' },
	{ file: 'client_balances.csv', summaryKey: 'client_balance', column: 'client_balance' },
	{ file: 'opening_balances.csv', summaryKey: 'receivable_total', column: 'receivable' },
	{ file: 'opening_balances.csv', summaryKey: 'credit_total', column: 'credit' },
	{ file: 'job_profitability.csv', summaryKey: 'revenue', column: 'revenue' },
	{ file: 'job_profitability.csv', summaryKey: 'total_cost', column: 'total_cost' },
	{ file: 'time_entries.csv', summaryKey: 'cost_total', column: 'cost_total' },
	{ file: 'uninvoiced_work.csv', summaryKey: 'uninvoiced', column: 'uninvoiced' },
	{ file: 'sales_outcomes.csv', summaryKey: 'won_value', column: 'estimated_value' }
];

export function buildReconciliationSummary(
	context: FinancialExportContext,
	results: LedgerResult[],
	omitted: { file: string; reason: string }[]
) {
	const byFile = new Map(results.map((result) => [result.file, result]));
	const summaries: Record<string, Row | null> = {};
	for (const result of results) {
		if (result.summary) summaries[result.file] = presentSummary(result.summary);
	}

	const checks = AGREEMENT_CHECKS.flatMap(({ file, summaryKey, column }) => {
		const result = byFile.get(file);
		const presented = result?.summary ? presentSummary(result.summary) : null;
		if (!result || !presented || !(summaryKey in presented) || !(column in result.columnTotals)) {
			return [];
		}
		// Won value is one outcome's rows, not the whole file; sum only what the summary counts.
		const rowsTotal =
			file === 'sales_outcomes.csv'
				? minorToMajor(result.columnTotals['won_estimated_value'] ?? 0n)
				: minorToMajor(result.columnTotals[column]);
		return [
			{
				file,
				summary_total: `${summaryKey} = ${presented[summaryKey]}`,
				rows_total: `sum(${column}) = ${rowsTotal}`,
				agrees: String(presented[summaryKey]) === rowsTotal
			}
		];
	});

	const sales = byFile.get('invoices_sales.csv')?.summary;
	const time = byFile.get('time_entries.csv')?.summary;
	const profitability = byFile.get('job_profitability.csv')?.summary;
	const exceptions: Row[] = [];
	if (sales && Number(sales.historical_status_only_closure_count) > 0) {
		exceptions.push({
			code: 'historical_status_only_closure',
			count: sales.historical_status_only_closure_count,
			meaning:
				'Invoices closed by the retired Mark Received action with no recorded Payment. They are unsettled: no cash was recorded for them.'
		});
	}
	if (sales && Number(sales.write_off_count) > 0) {
		exceptions.push({
			code: 'write_off',
			count: sales.write_off_count,
			meaning:
				'Sales written off as bad debt. The sale remains in invoices_sales.csv with written_off_at set.'
		});
	}
	const unratedCount = Number(time?.unrated_count ?? profitability?.unrated_labor_count ?? 0);
	if (unratedCount > 0) {
		exceptions.push({
			code: 'unrated_labor',
			count: unratedCount,
			minutes: time?.unrated_minutes ?? profitability?.unrated_labor_minutes,
			meaning:
				'Hours recorded with no labor rate on file. Excluded from cost rather than valued at zero.'
		});
	}
	return {
		export_type: 'financial_package',
		schema_version: FINANCIAL_EXPORT_SCHEMA_VERSION,
		generated_at: context.generatedAt.toISOString(),
		period: {
			from: context.from,
			to_exclusive: context.to,
			timezone: context.timezone,
			date_basis:
				'Inclusive start date, exclusive end date, in the organization timezone. Stored business dates (sale, payment, refund, expense, work) are not shifted.'
		},
		currency_code: context.currencyCode,
		balances_aged_as_of: context.agingAsOf,
		totals: summaries,
		agreement_checks: checks,
		exceptions,
		omitted_files: omitted
	};
}

export function buildManifest(
	context: FinancialExportContext,
	access: EffectiveOrganizationAccess,
	results: LedgerResult[],
	omitted: { file: string; reason: string }[]
) {
	const byFile = new Map(results.map((result) => [result.file, result]));
	return {
		export_type: 'financial_package',
		schema_version: FINANCIAL_EXPORT_SCHEMA_VERSION,
		generated_at: context.generatedAt.toISOString(),
		period: { from: context.from, to_exclusive: context.to, timezone: context.timezone },
		currency_code: context.currencyCode,
		money_format:
			'Major units with exactly two decimals (e.g. 1250.00) in currency_code; negative values carry a leading minus.',
		date_format: 'ISO 8601: dates as YYYY-MM-DD, instants as UTC timestamps.',
		files: FINANCIAL_LEDGERS.filter((ledger) => byFile.has(ledger.file)).map((ledger) => ({
			name: ledger.file,
			description: ledger.description,
			rows: byFile.get(ledger.file)!.rows,
			primary_key: ledger.primaryKey,
			columns: visibleColumns(ledger, access).map(csvHeaderFor),
			...(ledger.links ? { links: ledger.links } : {})
		})),
		omitted_files: omitted,
		companions: [
			{
				name: 'reconciliation_summary.json',
				description: 'Period totals, agreement checks and exceptions.'
			}
		]
	};
}

// Write the whole package to `sink` in order. Throws on the first reader failure; the route turns that into
// an aborted stream, and the caller simply downloads again.
export async function writeFinancialExport(
	supabase: SupabaseClient,
	access: EffectiveOrganizationAccess,
	context: FinancialExportContext,
	sink: FinancialExportSink
) {
	const state: { pending: Promise<void>; failure: Error | null } = {
		pending: Promise.resolve(),
		failure: null
	};
	const zip = new Zip((error, chunk) => {
		if (error) {
			state.failure = error;
			return;
		}
		state.pending = state.pending.then(() => sink(chunk));
	});

	const results: LedgerResult[] = [];
	const omitted: { file: string; reason: string }[] = [];
	for (const ledger of FINANCIAL_LEDGERS) {
		if (!ledger.allowed(access)) {
			omitted.push({ file: ledger.file, reason: 'permission_denied' });
			continue;
		}
		results.push(await writeLedger(supabase, zip, ledger, visibleColumns(ledger, access), context));
		if (state.failure) throw state.failure;
		// Let the sink drain between ledgers so a slow download applies backpressure to the reads.
		await state.pending;
	}

	addJson(
		zip,
		'reconciliation_summary.json',
		buildReconciliationSummary(context, results, omitted),
		context.generatedAt
	);
	addJson(
		zip,
		'manifest.json',
		buildManifest(context, access, results, omitted),
		context.generatedAt
	);
	zip.end();
	if (state.failure) throw state.failure;
	await state.pending;
}

// A stable download name that says what period it covers.
export function financialExportFileName(from: string, to: string) {
	return `accounting-export-${from}-to-${to}.zip`;
}
