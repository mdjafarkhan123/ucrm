export function formatCalendarDate(value: string | null) {
	if (!value) return 'Not recorded';
	const [year, month, day] = value.split('-').map(Number);
	return new Date(year, month - 1, day).toLocaleDateString('en-US', {
		year: 'numeric',
		month: 'long',
		day: 'numeric'
	});
}
export function formatDateTime(value: string | null) {
	if (!value) return 'Not recorded';
	return new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
}
export function formatPrice(cents: number | null, currency: string, period: string) {
	if (cents === null) return 'Not priced';
	return `$${(cents / 100).toFixed(2)} ${currency}/${period}`;
}
export function formatUsd(cents: number) {
	const sign = cents < 0 ? '-' : '';
	return `${sign}$${(Math.abs(cents) / 100).toLocaleString('en-US', {
		minimumFractionDigits: 2,
		maximumFractionDigits: 2
	})}`;
}
// A short "Mar 1 – Mar 31, 2026" range for a service period.
export function formatPeriod(start: string, end: string) {
	const toDate = (value: string) => {
		const [year, month, day] = value.split('-').map(Number);
		return new Date(year, month - 1, day);
	};
	const from = toDate(start);
	const to = toDate(end);
	const sameYear = from.getFullYear() === to.getFullYear();
	const startLabel = from.toLocaleDateString('en-US', {
		month: 'short',
		day: 'numeric',
		...(sameYear ? {} : { year: 'numeric' })
	});
	const endLabel = to.toLocaleDateString('en-US', {
		month: 'short',
		day: 'numeric',
		year: 'numeric'
	});
	return `${startLabel} – ${endLabel}`;
}
// "149", "149.5", "$1,149.50" -> cents; anything else (or zero and below) -> null.
export function parseUsdCents(value: string | number | null | undefined) {
	const text = String(value ?? '')
		.trim()
		.replace(/[$,\s]/g, '');
	if (!/^\d+(\.\d{1,2})?$/.test(text)) return null;
	const cents = Math.round(Number(text) * 100);
	return cents > 0 ? cents : null;
}
export function centsToInput(cents: number) {
	return (cents / 100).toFixed(2);
}
