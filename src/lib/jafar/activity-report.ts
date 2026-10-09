import { LEAD_SOURCES, type LeadSource } from './leads';

// Jafar business management C3: the activity report (plan § 6). What happened in a period, by where each business
// was found. The words the page, the query key and the API route share. The period lives in the URL, so a refresh
// or a shared link shows the same report; a hand-edited one falls back to this month.

export const REPORT_PERIODS = [
	'this_week',
	'this_month',
	'last_month',
	'last_90_days',
	'this_year',
	'all_time'
] as const;
export type ReportPeriod = (typeof REPORT_PERIODS)[number];

export const DEFAULT_REPORT_PERIOD: ReportPeriod = 'this_month';

export const REPORT_PERIOD_LABELS: Record<ReportPeriod, string> = {
	this_week: 'This week',
	this_month: 'This month',
	last_month: 'Last month',
	last_90_days: 'Last 90 days',
	this_year: 'This year',
	all_time: 'All time'
};

export function readReportPeriod(params: URLSearchParams): ReportPeriod {
	const value = params.get('period');
	return REPORT_PERIODS.find((period) => period === value) ?? DEFAULT_REPORT_PERIOD;
}

/** One source's counts, as `owner_activity_report` returns them. */
export type ReportRow = {
	source: LeadSource;
	/** Leads added. */
	researched: number;
	/** Businesses whose contact details were approved. */
	approved: number;
	/** Businesses we contacted, and every message or call that took. */
	reached: number;
	messages_sent: number;
	/** Businesses that got in touch or answered, and how many times. */
	replied: number;
	messages_received: number;
	calls_booked: number;
	calls_held: number;
	/** Businesses that were shown pricing. */
	pricing_shared: number;
	/** Deals won and lost; a won Deal's payment. */
	won: number;
	won_usd_cents: number;
	lost: number;
};

export type ActivityReport = { time_zone: string; sources: ReportRow[] };

export type ReportCount = Exclude<keyof ReportRow, 'source'>;

export type ReportStep = {
	key: ReportCount;
	label: string;
	/** A second count shown under the first: messages under people, calls booked under calls held. */
	detail?: { key: ReportCount; words: (count: number) => string };
};

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`;

/** The steps in the order a business moves through them. */
export const REPORT_STEPS: ReportStep[] = [
	{ key: 'researched', label: 'Leads added' },
	{ key: 'approved', label: 'Approved to contact' },
	{
		key: 'reached',
		label: 'Contacted',
		detail: { key: 'messages_sent', words: (n) => plural(n, 'message sent', 'messages sent') }
	},
	{
		key: 'replied',
		label: 'Replied',
		detail: {
			key: 'messages_received',
			words: (n) => plural(n, 'message received', 'messages received')
		}
	},
	{
		key: 'calls_held',
		label: 'Sales calls held',
		detail: { key: 'calls_booked', words: (n) => `${n} booked` }
	},
	{ key: 'pricing_shared', label: 'Pricing shared' },
	{ key: 'won', label: 'Won' },
	{ key: 'lost', label: 'Lost' }
];

/** Every source added together. */
export function reportTotals(rows: ReportRow[]): Record<ReportCount, number> {
	const totals = {} as Record<ReportCount, number>;
	for (const step of REPORT_STEPS) {
		totals[step.key] = 0;
		if (step.detail) totals[step.detail.key] = 0;
	}
	totals.won_usd_cents = 0;
	for (const row of rows)
		for (const key of Object.keys(totals) as ReportCount[]) totals[key] += row[key];
	return totals;
}

/** Sources in the Leads form's order, leaving out any with nothing in the period. */
export function reportRows(rows: ReportRow[]) {
	return LEAD_SOURCES.flatMap((source) => {
		const row = rows.find((candidate) => candidate.source === source);
		return row && Object.entries(row).some(([key, value]) => key !== 'source' && value !== 0)
			? [row]
			: [];
	});
}

function isoDate(date: Date) {
	const month = String(date.getMonth() + 1).padStart(2, '0');
	const day = String(date.getDate()).padStart(2, '0');
	return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * The first and last day of a period, both included, as of `today` (the viewer's own date). A week starts on
 * Monday. `from` is null for all time.
 */
export function reportRange(
	period: ReportPeriod,
	today: Date
): { from: string | null; to: string } {
	const year = today.getFullYear();
	const month = today.getMonth();
	const to = isoDate(today);
	switch (period) {
		case 'this_week': {
			const start = new Date(year, month, today.getDate() - ((today.getDay() + 6) % 7));
			return { from: isoDate(start), to };
		}
		case 'this_month':
			return { from: isoDate(new Date(year, month, 1)), to };
		case 'last_month':
			return { from: isoDate(new Date(year, month - 1, 1)), to: isoDate(new Date(year, month, 0)) };
		case 'last_90_days':
			return { from: isoDate(new Date(year, month, today.getDate() - 89)), to };
		case 'this_year':
			return { from: isoDate(new Date(year, 0, 1)), to };
		case 'all_time':
			return { from: null, to };
	}
}

export function reportParams(range: { from: string | null; to: string }) {
	const params = new URLSearchParams();
	if (range.from) params.set('from', range.from);
	params.set('to', range.to);
	return params;
}

export async function fetchActivityReport(range: {
	from: string | null;
	to: string;
}): Promise<ActivityReport> {
	const response = await fetch(`/api/jafar/leads/report?${reportParams(range)}`);
	if (!response.ok) throw new Error('The report could not be loaded.');
	return response.json();
}
