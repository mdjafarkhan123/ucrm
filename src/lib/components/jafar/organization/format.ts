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
