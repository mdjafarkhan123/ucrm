import type { JobRecurrenceInput } from './api';

const WEEKDAY_NAMES = [
	'Sunday',
	'Monday',
	'Tuesday',
	'Wednesday',
	'Thursday',
	'Friday',
	'Saturday'
];
const ORDINAL_NAMES: Record<number, string> = {
	1: 'first',
	2: 'second',
	3: 'third',
	4: 'fourth',
	5: 'last'
};

// A plain-English summary of the repeat rule, the way Jobber shows one ("Weekly on Mondays"). Read off the
// stored rule; the concrete visits carry the real count and range below it.
export function describeRecurrence(rule: JobRecurrenceInput | null): string {
	if (!rule) return '';
	const n = rule.interval_count ?? 1;
	switch (rule.frequency) {
		case 'daily':
			return n === 1 ? 'Daily' : `Every ${n} days`;
		case 'weekly': {
			const source = rule.weekdays?.length
				? rule.weekdays
				: [new Date(`${rule.start_date}T00:00`).getDay()];
			const list = source
				.slice()
				.sort((a, b) => a - b)
				.map((d) => WEEKDAY_NAMES[d])
				.join(', ');
			return n === 1 ? `Weekly on ${list}` : `Every ${n} weeks on ${list}`;
		}
		case 'monthly': {
			const prefix = n === 1 ? 'Monthly' : `Every ${n} months`;
			if (rule.monthly_mode === 'last_day') return `${prefix} on the last day`;
			if (
				rule.monthly_mode === 'day_of_week' &&
				rule.ordinal_week != null &&
				rule.ordinal_weekday != null
			) {
				return `${prefix} on the ${ORDINAL_NAMES[rule.ordinal_week] ?? ''} ${WEEKDAY_NAMES[rule.ordinal_weekday]}`;
			}
			if (rule.monthly_mode === 'day_of_month' && rule.month_day != null) {
				return `${prefix} on day ${rule.month_day}`;
			}
			return prefix;
		}
		case 'yearly':
			return n === 1 ? 'Yearly' : `Every ${n} years`;
		default:
			return '';
	}
}
