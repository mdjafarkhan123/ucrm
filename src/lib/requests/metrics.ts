import type { RequestWindow } from './api';

// The Requests list's New requests and Conversion rate cards, worked out the way Jobber does
// (help.getjobber.com, "List Pages and Key Metrics"): each card compares the last 30 days with the 30
// before as a percentage change, ((current - previous) / previous) x 100. With nothing to compare against
// there is no trend, only the plain period.

type Card = { value: string; note: string };

const PERIOD = 'Past 30 days';

function trendNote(current: number, previous: number | null) {
	if (previous === null || previous === 0) return PERIOD;
	const change = Math.round(((current - previous) / previous) * 100);
	if (change === 0) return `${PERIOD} · same as the 30 days before`;
	return `${PERIOD} · ${change > 0 ? '↑' : '↓'} ${Math.abs(change)}% vs the 30 days before`;
}

// A share of zero requests is not 0%, it is nothing yet.
function conversionRate(window: RequestWindow) {
	return window.new === 0 ? null : (window.converted / window.new) * 100;
}

export function newRequestsCard(current: RequestWindow, previous: RequestWindow): Card {
	return { value: String(current.new), note: trendNote(current.new, previous.new) };
}

export function conversionRateCard(current: RequestWindow, previous: RequestWindow): Card {
	const rate = conversionRate(current);
	if (rate === null) return { value: '—', note: 'No new requests in the past 30 days' };
	return { value: `${Math.round(rate)}%`, note: trendNote(rate, conversionRate(previous)) };
}

// The same trend the Conversion rate card carries, on its own, for the dark card that reads
// "16 of 26 new requests became a quote or job · ↑ 13% vs the 30 days before". Null when there is nothing
// to compare against, or when the rate has not moved enough to say.
export function conversionTrend(current: RequestWindow, previous: RequestWindow): string | null {
	const rate = conversionRate(current);
	const before = conversionRate(previous);
	if (rate === null || before === null || before === 0) return null;
	const change = Math.round(((rate - before) / before) * 100);
	if (change === 0) return 'same as the 30 days before';
	return `${change > 0 ? '↑' : '↓'} ${Math.abs(change)}% vs the 30 days before`;
}

// The same movement as conversionTrend, split for the dark card's pill: which way it went and the words
// beside the icon ("13% vs the 30 days before"). Null when there is nothing to compare against.
export function conversionChange(
	current: RequestWindow,
	previous: RequestWindow
): { direction: 'up' | 'down' | 'flat'; label: string } | null {
	const rate = conversionRate(current);
	const before = conversionRate(previous);
	if (rate === null || before === null || before === 0) return null;
	const change = Math.round(((rate - before) / before) * 100);
	if (change === 0) return { direction: 'flat', label: 'Same as the 30 days before' };
	return {
		direction: change > 0 ? 'up' : 'down',
		label: `${Math.abs(change)}% vs the 30 days before`
	};
}

// How much of the bar under the conversion figure is filled: the share of new requests that became a
// quote or job, 0 to 1. Null with no new requests, so no bar is drawn.
export function conversionShare(current: RequestWindow): number | null {
	return current.new === 0 ? null : Math.min(1, current.converted / current.new);
}
