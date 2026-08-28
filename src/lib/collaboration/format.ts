export function relativeTime(value: string, now = Date.now()) {
	const then = new Date(value).getTime();
	if (Number.isNaN(then)) return '';

	const seconds = Math.round((then - now) / 1000);
	const absolute = Math.abs(seconds);
	const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });

	// A database clock a second or two ahead of the browser otherwise renders a brand-new event as
	// "in 1 second", so anything inside a minute either way reads as just happened.
	if (absolute < 60) return 'Just now';
	if (absolute < 3600) return formatter.format(Math.round(seconds / 60), 'minute');
	if (absolute < 86400) return formatter.format(Math.round(seconds / 3600), 'hour');
	if (absolute < 2592000) return formatter.format(Math.round(seconds / 86400), 'day');
	if (absolute < 31536000) return formatter.format(Math.round(seconds / 2592000), 'month');
	return formatter.format(Math.round(seconds / 31536000), 'year');
}

export function exactTime(value: string) {
	const date = new Date(value);
	if (Number.isNaN(date.getTime())) return '';
	return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
		date
	);
}

// Groups activity into the "Today / Yesterday / date" headers Jobber's activity log uses.
export function dayLabel(value: string, now = new Date()) {
	const date = new Date(value);
	if (Number.isNaN(date.getTime())) return '';

	const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
	const diffDays = Math.round((startOfDay(now) - startOfDay(date)) / 86400000);

	if (diffDays === 0) return 'Today';
	if (diffDays === 1) return 'Yesterday';
	return new Intl.DateTimeFormat(undefined, {
		month: 'long',
		day: 'numeric',
		year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric'
	}).format(date);
}

// Collapses a message body to one line for a list-row preview, shared by every place that shows a
// snippet of a longer message rather than its full text.
export function previewText(value: string) {
	return value.replace(/\s+/g, ' ').trim();
}

export function formatFileSize(bytes: number) {
	if (bytes < 1024) return `${bytes} B`;
	if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
	return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function initials(name: string | null | undefined) {
	if (!name) return '?';
	const parts = name.trim().split(/\s+/).filter(Boolean);
	if (parts.length === 0) return '?';
	if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
	return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
}

// Deterministic color for a tag/avatar id so the same record always renders the same accent, without
// requiring anyone to pick a color. Matches the badge palette in the design system.
const TAG_COLORS = [
	'red',
	'orange',
	'green',
	'teal',
	'blue',
	'purple',
	'pink',
	'yellowGreen'
] as const;
export type TagColor = (typeof TAG_COLORS)[number];

export function colorForId(id: string): TagColor {
	let hash = 0;
	for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
	return TAG_COLORS[hash % TAG_COLORS.length];
}
