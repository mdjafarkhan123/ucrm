import { describe, it, expect } from 'vitest';
import { unzipSync, strFromU8 } from 'fflate';
import Papa from 'papaparse';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { EffectiveOrganizationAccess } from '$lib/server/access/effective';
import {
	FINANCIAL_LEDGERS,
	financialExportFileName,
	minorToMajor,
	writeFinancialExport,
	type FinancialExportContext
} from './financial-export';

// The package is proven here against a fake reader that behaves like the real ones: keyset paging by the
// cursor the ledger hands back, permission-hidden columns arriving as null, and one summary per ledger. What
// this cannot prove -- that the SQL itself sums correctly -- is the readers' own verified job.

const ALL_PERMISSIONS = [
	'invoices.view',
	'invoices.view_price',
	'jobs.view',
	'jobs.view_price',
	'jobs.view_cost',
	'time.track_team',
	'time.track_own',
	'expenses.manage_team',
	'expenses.record',
	'pipeline.view',
	'pipeline.view_value'
];

function accessWith(permissions: string[]): EffectiveOrganizationAccess {
	return {
		features: { 'sales.pipeline': true, 'core.jobs': true, 'core.invoices_payments': true },
		permissions: Object.fromEntries(permissions.map((key) => [key, true]))
	} as unknown as EffectiveOrganizationAccess;
}

const context: FinancialExportContext = {
	organizationId: 'org-1',
	from: '2026-08-01',
	to: '2026-09-01',
	timezone: 'Asia/Dhaka',
	currencyCode: 'BDT',
	agingAsOf: '2026-09-16',
	generatedAt: new Date('2026-09-16T10:00:00Z')
};

type Row = Record<string, unknown>;

// 1,203 invoices force three keyset pages; every other ledger fits in one.
const invoices: Row[] = Array.from({ length: 1203 }, (_, index) => ({
	invoice_id: `inv-${String(index).padStart(4, '0')}`,
	invoice_number: index + 1,
	root_invoice_id: `inv-${String(index).padStart(4, '0')}`,
	predecessor_invoice_id: null,
	client_id: 'cl-1',
	client_display_name: 'Acme, "Roofing"',
	client_company_name: null,
	subject: 'Roof repair',
	sale_date: '2026-08-15',
	recognition_basis: 'issued',
	currency_code: 'BDT',
	net_sales_minor: 10050,
	tax_minor: 1005,
	total_minor: 11055,
	written_off_at: index === 0 ? '2026-08-20T00:00:00Z' : null,
	has_unsettled_legacy_closure: index === 1,
	created_at: '2026-08-15T09:00:00Z'
}));

const paymentEvents: Row[] = [
	{
		event_id: 'pe-1',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		event_type: 'received',
		original_event_type: null,
		event_date: '2026-08-16',
		amount_minor: 5000,
		cash_effect_minor: 5000,
		currency_code: 'BDT',
		method: 'cash',
		reference: null,
		note: null,
		original_event_id: null,
		original_deposit_event_id: null,
		actor_user_id: 'user-secret',
		created_at: '2026-08-16T09:00:00Z'
	},
	{
		event_id: 'pe-2',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		event_type: 'refunded',
		original_event_type: null,
		event_date: '2026-08-17',
		amount_minor: 1250,
		cash_effect_minor: -1250,
		currency_code: 'BDT',
		method: 'cash',
		reference: null,
		note: null,
		original_event_id: 'pe-1',
		original_deposit_event_id: null,
		actor_user_id: 'user-secret',
		created_at: '2026-08-17T09:00:00Z'
	}
];

const timeEntries: Row[] = [
	{
		entry_id: 'te-1',
		started_at: '2026-08-10T03:00:00Z',
		started_on: '2026-08-10',
		minutes: 90,
		user_id: 'user-secret',
		user_name: 'Rafi',
		job_id: 'job-1',
		job_number: 7,
		job_title: 'Gutter clean',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		visit_id: null,
		visit_date: null,
		currency_code: 'BDT',
		is_unrated: false,
		cost_per_hour_minor: 2000,
		cost_total_minor: 3000
	}
];

const outcomes: Row[] = [
	{
		opportunity_id: 'op-1',
		outcome: 'won',
		outcome_at: '2026-08-05T10:00:00Z',
		outcome_on: '2026-08-05',
		created_on: '2026-08-01',
		source_kind: 'quote',
		request_id: null,
		quote_id: 'q-1',
		quote_number: 3,
		title: 'Fence',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		currency_code: 'BDT',
		estimated_value_minor: 250000,
		lost_reason: null,
		outcome_event_id: 'ev-1'
	},
	{
		opportunity_id: 'op-2',
		outcome: 'lost',
		outcome_at: '2026-08-06T10:00:00Z',
		outcome_on: '2026-08-06',
		created_on: '2026-08-01',
		source_kind: 'request',
		request_id: 'r-1',
		quote_id: null,
		quote_number: null,
		title: 'Deck',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		currency_code: 'BDT',
		estimated_value_minor: 99900,
		lost_reason: 'Price',
		outcome_event_id: 'ev-2'
	},
	// A Direct job is a won row, but never part of the summary's won_value.
	{
		opportunity_id: 'op-3',
		outcome: 'won',
		outcome_at: '2026-08-07T10:00:00Z',
		outcome_on: '2026-08-07',
		created_on: '2026-08-07',
		source_kind: 'direct_job',
		request_id: null,
		quote_id: null,
		job_id: 'j-1',
		quote_number: null,
		title: 'Gutter clean',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		currency_code: 'BDT',
		estimated_value_minor: 40000,
		lost_reason: null,
		outcome_event_id: 'ev-3'
	}
];

const openingBalances: Row[] = [
	{
		opening_balance_id: 'ob-1',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		currency_code: 'BDT',
		balance_type: 'receivable',
		receivable_minor: 10000,
		credit_minor: 0,
		as_of_date: '2026-07-01',
		source_note: 'Migrated from old system',
		root_opening_balance_id: 'ob-1',
		predecessor_opening_balance_id: null,
		import_batch_id: 'batch-1',
		created_at: '2026-07-01T09:00:00Z'
	},
	{
		opening_balance_id: 'ob-2',
		client_id: 'cl-1',
		client_display_name: 'Acme',
		client_company_name: null,
		currency_code: 'BDT',
		balance_type: 'credit',
		receivable_minor: 0,
		credit_minor: 5000,
		as_of_date: '2026-07-01',
		source_note: 'Deposit carried over',
		root_opening_balance_id: 'ob-2',
		predecessor_opening_balance_id: null,
		import_batch_id: 'batch-1',
		created_at: '2026-07-01T09:00:00Z'
	}
];

const pages: Record<string, Row[]> = {
	financial_invoice_sales_page: invoices,
	financial_invoice_tax_page: [],
	financial_payment_events_page: paymentEvents,
	financial_payment_allocations_page: [],
	financial_deposit_credits_page: [],
	financial_client_aging_page: [],
	financial_opening_balances_page: openingBalances,
	financial_job_profitability_page: [],
	financial_time_entries_page: timeEntries,
	financial_expenses_page: [],
	financial_uninvoiced_work_page: [],
	financial_sales_outcomes_page: outcomes
};

const summaries: Record<string, Row> = {
	financial_invoice_sales_summary: {
		net_sales_minor: 1203 * 10050,
		tax_minor: 1203 * 1005,
		billed_total_minor: 1203 * 11055,
		write_off_count: 1,
		historical_status_only_closure_count: 1
	},
	financial_payment_events_summary: {
		received_minor: 5000,
		refunded_minor: 1250,
		reversed_receipt_minor: 0,
		reversed_refund_minor: 0,
		cash_effect_minor: 3750,
		event_count: 2
	},
	financial_time_entries_summary: {
		entry_count: 1,
		member_count: 1,
		job_count: 1,
		minutes: 90,
		rated_minutes: 90,
		unrated_count: 0,
		unrated_minutes: 0,
		cost_total_minor: 3000
	},
	financial_sales_outcomes_summary: {
		won_count: 1,
		lost_count: 1,
		won_unvalued_count: 0,
		lost_unvalued_count: 0,
		won_value_minor: 250000,
		lost_value_minor: 99900,
		direct_job_count: 1,
		direct_job_unvalued_count: 0,
		direct_job_value_minor: 40000
	},
	financial_opening_balances_summary: {
		receivable_total_minor: 10000,
		credit_total_minor: 5000,
		net_minor: 5000,
		fact_count: 2
	}
};

// Mirrors the readers' keyset contract: rows strictly after the cursor's key, in ascending order.
function fakeSupabase(calls: { fn: string; args: Record<string, unknown> }[]) {
	return {
		rpc(fn: string, args: Record<string, unknown>) {
			calls.push({ fn, args });
			if (fn.endsWith('_summary')) {
				return Promise.resolve({ data: [summaries[fn] ?? {}], error: null });
			}
			const rows = pages[fn];
			if (!rows) return Promise.resolve({ data: null, error: { message: `no reader ${fn}` } });
			const cursorKey = Object.keys(args).find(
				(key) => key.startsWith('cursor_') && key.endsWith('_id')
			);
			let start = 0;
			if (cursorKey && args[cursorKey] != null) {
				const idColumn = cursorKey.slice('cursor_'.length);
				start = rows.findIndex((row) => row[idColumn] === args[cursorKey]) + 1;
			}
			return Promise.resolve({
				data: rows.slice(start, start + Number(args.page_limit)),
				error: null
			});
		}
	} as unknown as SupabaseClient;
}

async function packageFor(access: EffectiveOrganizationAccess) {
	const calls: { fn: string; args: Record<string, unknown> }[] = [];
	const chunks: Uint8Array[] = [];
	await writeFinancialExport(fakeSupabase(calls), access, context, async (chunk) => {
		chunks.push(chunk);
	});
	const total = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
	const bytes = new Uint8Array(total);
	let offset = 0;
	for (const chunk of chunks) {
		bytes.set(chunk, offset);
		offset += chunk.byteLength;
	}
	const files = unzipSync(bytes);
	const csv = (name: string) =>
		Papa.parse<Record<string, string>>(strFromU8(files[name]), {
			header: true,
			skipEmptyLines: true
		}).data;
	const json = (name: string) => JSON.parse(strFromU8(files[name]));
	return { files, csv, json, calls };
}

describe('minorToMajor', () => {
	it('writes fixed two-decimal major units without floating point', () => {
		expect(minorToMajor(0)).toBe('0.00');
		expect(minorToMajor(5)).toBe('0.05');
		expect(minorToMajor(1250)).toBe('12.50');
		expect(minorToMajor(-1250)).toBe('-12.50');
		expect(minorToMajor('9007199254740993')).toBe('90071992547409.93');
		expect(minorToMajor(null)).toBe('');
	});
});

describe('writeFinancialExport', () => {
	it('pages every ledger to the end and writes rows, summary and manifest that agree', async () => {
		const { files, csv, json, calls } = await packageFor(accessWith(ALL_PERMISSIONS));

		expect(Object.keys(files).sort()).toEqual(
			[
				...FINANCIAL_LEDGERS.map((ledger) => ledger.file),
				'manifest.json',
				'reconciliation_summary.json'
			].sort()
		);

		// Three pages for 1,203 invoices, each continuing from the previous last row.
		const invoicePages = calls.filter((call) => call.fn === 'financial_invoice_sales_page');
		expect(invoicePages.map((call) => call.args.cursor_invoice_id)).toEqual([
			undefined,
			'inv-0499',
			'inv-0999'
		]);
		const sales = csv('invoices_sales.csv');
		expect(sales).toHaveLength(1203);
		expect(Object.keys(sales[0])).toEqual([
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
			'net_sales',
			'tax',
			'total',
			'written_off_at',
			'has_unsettled_legacy_closure',
			'created_at'
		]);
		expect(sales[0].net_sales).toBe('100.50');
		expect(sales[0].client_display_name).toBe('Acme, "Roofing"');

		// The corrections file is the filtered view; internal user ids never appear.
		expect(csv('payment_events.csv')).toHaveLength(2);
		const corrections = csv('refunds_reversals.csv');
		expect(corrections).toHaveLength(1);
		expect(corrections[0].event_type).toBe('refunded');
		expect(corrections[0].cash_effect).toBe('-12.50');
		expect(corrections[0].original_event_id).toBe('pe-1');
		expect(strFromU8(files['payment_events.csv'])).not.toContain('user-secret');
		expect(strFromU8(files['time_entries.csv'])).not.toContain('user-secret');

		const openingBalanceRows = csv('opening_balances.csv');
		expect(openingBalanceRows).toHaveLength(2);
		expect(openingBalanceRows[0].receivable).toBe('100.00');
		expect(openingBalanceRows[1].credit).toBe('50.00');

		const manifest = json('manifest.json');
		expect(manifest.schema_version).toBe(2);
		expect(manifest.currency_code).toBe('BDT');
		expect(manifest.period).toEqual({
			from: '2026-08-01',
			to_exclusive: '2026-09-01',
			timezone: 'Asia/Dhaka'
		});
		const manifestRows = Object.fromEntries(
			manifest.files.map((file: { name: string; rows: number }) => [file.name, file.rows])
		);
		expect(manifestRows['invoices_sales.csv']).toBe(1203);
		expect(manifestRows['refunds_reversals.csv']).toBe(1);
		expect(manifestRows['sales_outcomes.csv']).toBe(3);
		expect(manifestRows['opening_balances.csv']).toBe(2);
		expect(manifest.omitted_files).toEqual([]);

		const summary = json('reconciliation_summary.json');
		expect(summary.totals['invoices_sales.csv']).toEqual({
			net_sales: '120901.50',
			tax: '12090.15',
			billed_total: '132991.65',
			write_off_count: 1,
			historical_status_only_closure_count: 1
		});
		expect(summary.totals['opening_balances.csv']).toEqual({
			receivable_total: '100.00',
			credit_total: '50.00',
			net: '50.00',
			fact_count: 2
		});
		expect(summary.agreement_checks.every((check: { agrees: boolean }) => check.agrees)).toBe(true);
		const wonCheck = summary.agreement_checks.find(
			(check: { file: string }) => check.file === 'sales_outcomes.csv'
		);
		expect(wonCheck.rows_total).toBe('sum(estimated_value) = 2500.00');
		expect(summary.exceptions.map((exception: { code: string }) => exception.code)).toEqual([
			'historical_status_only_closure',
			'write_off'
		]);
	});

	it('omits ledgers and columns the caller may not see instead of writing zeros', async () => {
		const { files, csv, json, calls } = await packageFor(
			accessWith([
				'invoices.view',
				'invoices.view_price',
				'jobs.view',
				'jobs.view_price',
				'time.track_own',
				'pipeline.view'
			])
		);

		expect(files['expenses.csv']).toBeUndefined();
		expect(calls.some((call) => call.fn === 'financial_expenses_page')).toBe(false);

		const entries = csv('time_entries.csv');
		expect(Object.keys(entries[0])).not.toContain('cost_total');
		expect(Object.keys(entries[0])).not.toContain('cost_per_hour');
		expect(entries[0].minutes).toBe('90');

		const won = csv('sales_outcomes.csv');
		expect(Object.keys(won[0])).not.toContain('estimated_value');

		const manifest = json('manifest.json');
		expect(manifest.omitted_files).toEqual([{ file: 'expenses.csv', reason: 'permission_denied' }]);
		const summary = json('reconciliation_summary.json');
		expect(
			summary.agreement_checks.some(
				(check: { file: string }) => check.file === 'sales_outcomes.csv'
			)
		).toBe(false);
	});

	it('names the download after the period', () => {
		expect(financialExportFileName('2026-08-01', '2026-09-01')).toBe(
			'accounting-export-2026-08-01-to-2026-09-01.zip'
		);
	});
});
