import type { InvoiceOverview } from '$lib/invoices/api';
import type { JobOverview } from '$lib/jobs/api';
import type { QuoteOverview } from '$lib/quotes/api';
import type { RequestOverview } from '$lib/requests/api';

// The "To do" card on Home: work waiting at each stage, across the whole business. Every count comes from the
// same overview the matching list page already draws, so Home and the list can never disagree. A line carries
// a value only where that overview already holds one; nothing here adds up prices on the side.

export type TodoColumnKey = 'requests' | 'quotes' | 'jobs' | 'invoices';

export type TodoLine = {
	/** The list status this line stands for, and the filter its link names. */
	key: string;
	label: string;
	hint: string;
	/** Null while the overview is still loading. */
	count: number | null;
	/** Money for the line, in minor units, where the overview has it. */
	valueMinor: number | null;
	/** The status colour of the line's dot and count: `neutral` lines carry no dot. */
	tone: TodoTone;
};

export type TodoTone = 'neutral' | 'success' | 'warning' | 'critical' | 'informative';

export type TodoColumn = {
	key: TodoColumnKey;
	title: string;
	lines: TodoLine[];
	/** The sum of the lines, shown in the chip beside the title; null while any line is loading. */
	total: number | null;
};

type LineSpec = { key: string; label: string; hint: string; tone: TodoTone };

const REQUEST_LINES: LineSpec[] = [
	{ key: 'needs_approval', label: 'Needs approval', hint: 'Website bookings to confirm', tone: 'warning' },
	{ key: 'new', label: 'New', hint: 'Not looked at yet', tone: 'neutral' },
	{ key: 'assessment_completed', label: 'Assessment complete', hint: 'Ready to quote', tone: 'neutral' }
];
const QUOTE_LINES: LineSpec[] = [
	{ key: 'approved', label: 'Approved', hint: 'Ready to become a job', tone: 'success' },
	{ key: 'changes_requested', label: 'Changes requested', hint: 'Customer asked for edits', tone: 'warning' },
	{ key: 'draft', label: 'Draft', hint: 'Not sent yet', tone: 'neutral' }
];
const JOB_LINES: LineSpec[] = [
	{ key: 'requires_invoicing', label: 'Requires invoicing', hint: 'Work done, not billed yet', tone: 'warning' },
	{ key: 'action_required', label: 'Action required', hint: 'No upcoming visit booked', tone: 'critical' },
	{ key: 'ending_soon', label: 'Ending soon', hint: 'Recurring, ends within 30 days', tone: 'neutral' }
];
const INVOICE_LINES: LineSpec[] = [
	{ key: 'draft', label: 'Draft', hint: 'Not sent yet', tone: 'neutral' },
	{ key: 'awaiting_payment', label: 'Awaiting payment', hint: 'Sent, not due yet', tone: 'informative' },
	{ key: 'past_due', label: 'Past due', hint: 'Past the due date', tone: 'critical' }
];

function column(
	key: TodoColumnKey,
	title: string,
	specs: LineSpec[],
	counts: Record<string, number> | undefined,
	value: (spec: LineSpec) => number | null = () => null
): TodoColumn {
	const lines = specs.map<TodoLine>((spec) => ({
		...spec,
		count: counts ? (counts[spec.key] ?? 0) : null,
		valueMinor: counts ? value(spec) : null
	}));
	const loaded = lines.every((line) => line.count !== null);
	return {
		key,
		title,
		lines,
		total: loaded ? lines.reduce((sum, line) => sum + (line.count ?? 0), 0) : null
	};
}

/** The money a reader may see on the Invoices column: not-yet-due and past-due, split the way the Invoices
 * page splits them. Null when this reader has no invoice price access. */
export function invoiceTodoMoney(overview: InvoiceOverview | undefined) {
	const outstanding = overview?.outstanding_minor ?? null;
	const overdue = overview?.overdue_minor ?? null;
	if (outstanding === null || overdue === null) return { awaiting: null, pastDue: null };
	return { awaiting: Math.max(outstanding - overdue, 0), pastDue: overdue };
}

export function buildTodoColumns(
	allowed: Record<TodoColumnKey, boolean>,
	data: {
		requests?: Pick<RequestOverview, 'counts'>;
		quotes?: Pick<QuoteOverview, 'counts'>;
		jobs?: Pick<JobOverview, 'counts'>;
		invoices?: InvoiceOverview;
	}
): TodoColumn[] {
	const columns: TodoColumn[] = [];
	if (allowed.requests)
		columns.push(column('requests', 'Requests', REQUEST_LINES, data.requests?.counts));
	if (allowed.quotes) columns.push(column('quotes', 'Quotes', QUOTE_LINES, data.quotes?.counts));
	if (allowed.jobs) columns.push(column('jobs', 'Jobs', JOB_LINES, data.jobs?.counts));
	if (allowed.invoices) {
		const money = invoiceTodoMoney(data.invoices);
		columns.push(
			column('invoices', 'Invoices', INVOICE_LINES, data.invoices?.counts, (spec) =>
				spec.key === 'awaiting_payment' ? money.awaiting : spec.key === 'past_due' ? money.pastDue : null
			)
		);
	}
	return columns;
}
