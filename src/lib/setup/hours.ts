// The two setup answers that are more than one line of text: the normal week, and the dated days that
// differ from it. The same shape as Google Business Profile's regular hours and special hours, because
// that is where most of these answers end up. Both travel between the page and the server as JSON text
// and are stored as JSON, so the page, the server's validation and the tests all read these functions.

const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
const DATE_PATTERN = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

export const HOURS_PERIODS_PER_DAY = 3;
export const HOURS_EXCEPTIONS_MAX = 40;
export const HOURS_EXCEPTION_NAME_MAX = 60;

/** Opening and closing time as HH:MM. A closing time earlier than opening runs past midnight. */
export type SetupHoursPeriod = [opens: string, closes: string];

export type SetupHoursDay = { open: boolean; all_day: boolean; periods: SetupHoursPeriod[] };

export type SetupHours =
	| { mode: 'appointment_only' }
	/** Seven days, Sunday first — the same order as the Business Hours screen. */
	| { mode: 'weekly'; days: SetupHoursDay[] };

export type SetupHoursException = {
	/** YYYY-MM-DD. */
	date: string;
	name: string;
	closed: boolean;
	opens: string | null;
	closes: string | null;
};

type Parsed<T> = { value: T; error: null } | { value: null; error: string };

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseJson(raw: string): unknown {
	try {
		return JSON.parse(raw);
	} catch {
		return undefined;
	}
}

function parsePeriod(input: unknown): SetupHoursPeriod | null {
	if (!Array.isArray(input) || input.length !== 2) return null;
	const [opens, closes] = input;
	if (typeof opens !== 'string' || typeof closes !== 'string') return null;
	if (!TIME_PATTERN.test(opens) || !TIME_PATTERN.test(closes) || opens === closes) return null;
	return [opens, closes];
}

function parseDay(input: unknown): SetupHoursDay | null {
	if (!isRecord(input) || typeof input.open !== 'boolean' || typeof input.all_day !== 'boolean')
		return null;
	if (!Array.isArray(input.periods) || input.periods.length > HOURS_PERIODS_PER_DAY) return null;
	const periods: SetupHoursPeriod[] = [];
	for (const item of input.periods) {
		const period = parsePeriod(item);
		if (!period) return null;
		periods.push(period);
	}
	// A closed day and an all-day day carry no times; an ordinary open day carries at least one period.
	if (!input.open && (input.all_day || periods.length > 0)) return null;
	if (input.open && input.all_day && periods.length > 0) return null;
	if (input.open && !input.all_day && periods.length === 0) return null;
	return { open: input.open, all_day: input.all_day, periods };
}

const HOURS_ERROR = 'Set your opening hours again — they could not be read.';

export function parseSetupHours(raw: string): Parsed<SetupHours> {
	const input = parseJson(raw);
	if (!isRecord(input)) return { value: null, error: HOURS_ERROR };
	if (input.mode === 'appointment_only')
		return { value: { mode: 'appointment_only' }, error: null };
	if (input.mode !== 'weekly' || !Array.isArray(input.days) || input.days.length !== 7)
		return { value: null, error: HOURS_ERROR };

	const days: SetupHoursDay[] = [];
	for (const item of input.days) {
		const day = parseDay(item);
		if (!day) return { value: null, error: HOURS_ERROR };
		days.push(day);
	}
	if (!days.some((day) => day.open))
		return {
			value: null,
			error: 'Open at least one day, or choose “By appointment only”.'
		};
	return { value: { mode: 'weekly', days }, error: null };
}

const EXCEPTIONS_ERROR = 'Set these dates again — they could not be read.';

export function parseSetupHoursExceptions(raw: string): Parsed<SetupHoursException[]> {
	const input = parseJson(raw);
	if (!Array.isArray(input) || input.length === 0) return { value: null, error: EXCEPTIONS_ERROR };
	if (input.length > HOURS_EXCEPTIONS_MAX)
		return { value: null, error: `Keep this to ${HOURS_EXCEPTIONS_MAX} dates.` };

	const seen = new Set<string>();
	const exceptions: SetupHoursException[] = [];
	for (const item of input) {
		if (!isRecord(item) || typeof item.date !== 'string' || !DATE_PATTERN.test(item.date))
			return { value: null, error: EXCEPTIONS_ERROR };
		if (seen.has(item.date))
			return { value: null, error: 'Two of these are the same date. Keep one of them.' };
		seen.add(item.date);

		const name = typeof item.name === 'string' ? item.name.trim() : '';
		if (name.length > HOURS_EXCEPTION_NAME_MAX)
			return { value: null, error: `Keep each name under ${HOURS_EXCEPTION_NAME_MAX} characters.` };

		if (item.closed === true) {
			exceptions.push({ date: item.date, name, closed: true, opens: null, closes: null });
			continue;
		}
		const period = item.closed === false ? parsePeriod([item.opens, item.closes]) : null;
		if (!period) return { value: null, error: EXCEPTIONS_ERROR };
		exceptions.push({
			date: item.date,
			name,
			closed: false,
			opens: period[0],
			closes: period[1]
		});
	}
	exceptions.sort((a, b) => a.date.localeCompare(b.date));
	return { value: exceptions, error: null };
}

type BusinessHourRow = {
	weekday: number;
	period_index: number;
	is_open: boolean;
	is_open_24h: boolean;
	opens_at: string | null;
	closes_at: string | null;
};

/** The hours already saved in Settings, as a setup answer — or null when there is nothing to offer. */
export function setupHoursFromBusinessHours(
	mode: string | null | undefined,
	rows: BusinessHourRow[]
): SetupHours | null {
	if (mode === 'appointment_only') return { mode: 'appointment_only' };
	if (mode !== 'weekly') return null;

	const days = [0, 1, 2, 3, 4, 5, 6].map((weekday): SetupHoursDay => {
		const dayRows = rows
			.filter((row) => row.weekday === weekday && row.is_open)
			.sort((a, b) => a.period_index - b.period_index);
		if (dayRows.some((row) => row.is_open_24h)) return { open: true, all_day: true, periods: [] };
		const periods = dayRows
			.map((row) => parsePeriod([row.opens_at?.slice(0, 5), row.closes_at?.slice(0, 5)]))
			.filter((period): period is SetupHoursPeriod => period !== null)
			.slice(0, HOURS_PERIODS_PER_DAY);
		return periods.length > 0
			? { open: true, all_day: false, periods }
			: { open: false, all_day: false, periods: [] };
	});
	return days.some((day) => day.open) ? { mode: 'weekly', days } : null;
}
