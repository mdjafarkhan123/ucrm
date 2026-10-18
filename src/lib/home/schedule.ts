import type { ScheduleWindowPage } from '$lib/schedule/api';
import { assessmentToItem, taskToItem, visitToItem, type ScheduleItem } from '$lib/schedule/items';
import { addDays } from '$lib/home/money';

// Today's schedule on Home. It reads the same window the Schedule page reads, and the same three statuses
// the Schedule draws (Completed, Today, Late), so the two screens never disagree. Home calls an item that is
// neither completed nor late "Still to do". Nothing here knows a visit's price or whether a timer runs on
// it: the window read carries neither, so Home shows neither.

/** How many earlier days Home looks back for work that was never completed. */
export const LATE_LOOKBACK_DAYS = 14;

export type HomeScheduleStatus = 'completed' | 'todo' | 'late';
export type HomeScheduleRoute =
	| { page: 'job'; id: string }
	| { page: 'request'; id: string }
	| { page: 'pipeline' };

export type HomeScheduleRow = {
	key: string;
	kind: 'visit' | 'assessment' | 'task';
	group: 'late' | 'today';
	status: HomeScheduleStatus;
	/** The time column: `7:30` over `AM`, `Anytime` alone, or a late day's weekday over its date (`Fri` over
	 * `16 Oct`). */
	timeTop: string;
	timeBottom: string;
	/** The work itself (`Decking install`); `title` adds the client in front, for one-line uses. */
	work: string;
	client: string | null;
	title: string;
	/** Address and length, e.g. `5120 Imperial St, Burnaby`; null when this reader may not see either. */
	place: string | null;
	length: string | null;
	assigneeIds: string[];
	route: HomeScheduleRoute;
	date: string;
	/** Minutes past midnight, null for anytime work. */
	startMinutes: number | null;
};

export type HomePersonLoad = { id: string | null; done: number; total: number };

export type HomeSchedule = {
	late: HomeScheduleRow[];
	today: HomeScheduleRow[];
	counts: { total: number; completed: number; todo: number; late: number; unassigned: number };
	/** How many different people have work today. */
	peopleOut: number;
	/** The latest end time among today's timed work, as minutes past midnight. */
	lastEndMinutes: number | null;
	byPerson: HomePersonLoad[];
};

export function scheduleWindowFor(today: string) {
	return { from: addDays(today, -LATE_LOOKBACK_DAYS), to: today };
}

function minutesOf(clock: string | null): number | null {
	if (!clock) return null;
	const [hour, minute] = clock.split(':').map(Number);
	return Number.isFinite(hour) ? hour * 60 + (Number.isFinite(minute) ? minute : 0) : null;
}

/** `7:30` / `AM`, from minutes past midnight. */
export function clockTile(minutes: number): { top: string; bottom: string } {
	const hour = Math.floor(minutes / 60);
	const minute = minutes % 60;
	const twelve = hour % 12 === 0 ? 12 : hour % 12;
	return { top: `${twelve}:${String(minute).padStart(2, '0')}`, bottom: hour < 12 ? 'AM' : 'PM' };
}

/** `7:30 AM`, for sentences. */
export function clockSentence(minutes: number): string {
	const tile = clockTile(minutes);
	return `${tile.top} ${tile.bottom}`;
}

function lengthLabel(start: number | null, end: number | null): string | null {
	if (start === null || end === null || end <= start) return null;
	const minutes = end - start;
	if (minutes < 60) return `${minutes} min`;
	const hours = minutes / 60;
	return `${Number.isInteger(hours) ? hours : Math.round(hours * 10) / 10} hr`;
}

function lateTile(day: string): { top: string; bottom: string } {
	const date = new Date(`${day}T00:00:00Z`);
	return {
		top: new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'UTC' }).format(date),
		bottom: new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(
			date
		)
	};
}

function clientOf(item: ScheduleItem): string | null {
	if (item.kind === 'event') return null;
	return item.client_name ?? item.client_company_name ?? null;
}

function placeOf(item: ScheduleItem): string | null {
	if (item.kind === 'event' || item.kind === 'task') return null;
	return [item.property_address_line1, item.property_city].filter(Boolean).join(', ') || null;
}

function workOf(item: ScheduleItem): string {
	if (item.kind === 'event' || item.kind === 'task') return item.title;
	return item.kind === 'visit'
		? (item.title ?? item.job_title ?? `Job #${item.job_number ?? ''}`.trim())
		: (item.request_title ?? 'Assessment');
}

function titleOf(item: ScheduleItem): string {
	if (item.kind === 'event') return item.title;
	const client = clientOf(item) ?? (item.kind === 'task' ? null : 'Client hidden');
	return client ? `${client} · ${workOf(item)}` : workOf(item);
}

function routeOf(item: ScheduleItem): HomeScheduleRoute | null {
	if (item.kind === 'visit') return { page: 'job', id: item.job_id };
	if (item.kind === 'assessment') return { page: 'request', id: item.request_id };
	if (item.kind === 'task') return { page: 'pipeline' };
	return null;
}

function rowFor(item: ScheduleItem, today: string): HomeScheduleRow | null {
	const route = routeOf(item);
	const date = item.visit_date;
	if (!route || !date || item.kind === 'event') return null;
	const completed = item.completed_at !== null;
	// Same rule as `visitDerivedStatus`: the day is the unit, so work booked for earlier today is not late.
	const isLate = !completed && date < today;
	if (date > today || (date < today && completed)) return null;
	const start = minutesOf(item.start_time);
	const end = minutesOf(item.end_time);
	let tile: { top: string; bottom: string };
	if (isLate) tile = lateTile(date);
	else if (start === null) tile = { top: 'Anytime', bottom: '' };
	else tile = clockTile(start);
	const length = lengthLabel(start, end);
	return {
		key: `${item.kind}:${item.id}`,
		kind: item.kind,
		group: isLate ? 'late' : 'today',
		status: completed ? 'completed' : isLate ? 'late' : 'todo',
		timeTop: tile.top,
		timeBottom: tile.bottom,
		work: workOf(item),
		client: clientOf(item) ?? (item.kind === 'task' ? null : 'Client hidden'),
		title: titleOf(item),
		place: placeOf(item) ?? (item.kind === 'task' ? 'Pipeline task' : null),
		length: isLate && length === null ? null : length,
		assigneeIds: item.assignee_ids,
		route,
		date,
		startMinutes: start
	};
}

/** Late first (oldest day first), then today's timed work in time order, then anytime work. */
function compareRows(a: HomeScheduleRow, b: HomeScheduleRow) {
	if (a.date !== b.date) return a.date < b.date ? -1 : 1;
	if (a.startMinutes === null && b.startMinutes !== null) return 1;
	if (a.startMinutes !== null && b.startMinutes === null) return -1;
	if (a.startMinutes !== null && b.startMinutes !== null && a.startMinutes !== b.startMinutes)
		return a.startMinutes - b.startMinutes;
	return a.key < b.key ? -1 : 1;
}

export function buildHomeSchedule(
	page: ScheduleWindowPage,
	timezone: string,
	today: string
): HomeSchedule {
	const items: ScheduleItem[] = [
		...page.visits.map(visitToItem),
		...page.assessments.map((assessment) => assessmentToItem(assessment, timezone)),
		...(page.tasks ?? []).map(taskToItem)
	];
	const rows = items
		.map((item) => rowFor(item, today))
		.filter((row): row is HomeScheduleRow => row !== null)
		.sort(compareRows);
	const late = rows.filter((row) => row.group === 'late');
	const todayRows = rows.filter((row) => row.group === 'today');

	const people = new Map<string | null, HomePersonLoad>();
	for (const row of todayRows) {
		for (const id of row.assigneeIds.length > 0 ? row.assigneeIds : [null]) {
			const load = people.get(id) ?? { id, done: 0, total: 0 };
			load.total += 1;
			if (row.status === 'completed') load.done += 1;
			people.set(id, load);
		}
	}
	let lastEnd: number | null = null;
	for (const item of items) {
		if (item.kind === 'event' || item.visit_date !== today) continue;
		const end = minutesOf(item.end_time);
		if (end !== null && (lastEnd === null || end > lastEnd)) lastEnd = end;
	}
	const completed = todayRows.filter((row) => row.status === 'completed').length;
	return {
		late,
		today: todayRows,
		counts: {
			total: todayRows.length,
			completed,
			todo: todayRows.length - completed,
			late: late.length,
			unassigned: todayRows.filter(
				(row) => row.assigneeIds.length === 0 && row.status !== 'completed'
			).length
		},
		peopleOut: [...people.keys()].filter((id) => id !== null).length,
		lastEndMinutes: lastEnd,
		byPerson: [...people.values()].sort(
			(a, b) => (a.id === null ? 1 : 0) - (b.id === null ? 1 : 0) || b.total - a.total
		)
	};
}
