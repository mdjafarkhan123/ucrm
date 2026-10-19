import { browser } from '$app/environment';

// How tall an hour is drawn on the time-based views. This is a per-reader viewing preference -- a zoom, not a
// filter -- so it lives in the browser and never touches the URL, the window read or anyone else's screen.
// Compact is the default and the size the approved design draws.

export type ScheduleZoom = 'compact' | 'comfortable' | 'spacious';

export const SCHEDULE_ZOOMS: ScheduleZoom[] = ['compact', 'comfortable', 'spacious'];

export const SCHEDULE_ZOOM_LABELS: Record<ScheduleZoom, string> = {
	compact: 'Compact',
	comfortable: 'Comfortable',
	spacious: 'Spacious'
};

/** Pixels per hour down a Week day column. Compact is the height the approved design draws. */
export const WEEK_HOUR_PX: Record<ScheduleZoom, number> = {
	compact: 64,
	comfortable: 84,
	spacious: 108
};

/** Pixels per hour across a Day board row. Compact is the board's original width. */
export const DAY_HOUR_PX: Record<ScheduleZoom, number> = {
	compact: 64,
	comfortable: 84,
	spacious: 108
};

const STORAGE_KEY = 'ucrm.schedule.zoom';

function isZoom(value: unknown): value is ScheduleZoom {
	return value === 'compact' || value === 'comfortable' || value === 'spacious';
}

/** The reader's saved choice, or Compact when there is none or the browser will not say. */
export function readScheduleZoom(): ScheduleZoom {
	if (!browser) return 'compact';
	try {
		const stored = localStorage.getItem(STORAGE_KEY);
		return isZoom(stored) ? stored : 'compact';
	} catch {
		return 'compact';
	}
}

export function writeScheduleZoom(zoom: ScheduleZoom): void {
	if (!browser) return;
	try {
		localStorage.setItem(STORAGE_KEY, zoom);
	} catch {
		// A private window or blocked storage just means the choice is not remembered this time.
	}
}
