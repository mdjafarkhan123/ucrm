// The "Waiting 25 min" line under a request's Requested date. Only requests still waiting on the office
// for a first reply carry it: a new request nobody has acted on, and a website booking asking for a time.
// Rounded down the way people say it: minutes under an hour, hours under a day, then days.
const WAITING_STATUSES = new Set(['new', 'needs_approval']);

export function waitingLabel(status: string, requestedAt: string, now = new Date()): string | null {
	if (!WAITING_STATUSES.has(status)) return null;
	const elapsed = now.getTime() - new Date(requestedAt).getTime();
	if (!Number.isFinite(elapsed)) return null;
	const minutes = Math.max(1, Math.floor(elapsed / 60_000));
	if (minutes < 60) return `Waiting ${minutes} min`;
	const hours = Math.floor(minutes / 60);
	if (hours < 24) return `Waiting ${hours} h`;
	const days = Math.floor(hours / 24);
	return `Waiting ${days} ${days === 1 ? 'day' : 'days'}`;
}
