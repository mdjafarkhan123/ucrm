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
