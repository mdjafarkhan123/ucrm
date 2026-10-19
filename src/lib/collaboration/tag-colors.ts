// Stored light hex values map to semantic families, which follow the active theme.
export const tagColors = [
	{ name: 'Grey', hex: '#49646f', token: 'inactive' },
	{ name: 'Red', hex: '#d24232', token: 'critical' },
	{ name: 'Orange', hex: '#b36109', token: 'request' },
	{ name: 'Yellow', hex: '#86761d', token: 'review' },
	{ name: 'Green', hex: '#049a54', token: 'job' },
	{ name: 'Teal', hex: '#118197', token: 'conversation' },
	{ name: 'Blue', hex: '#225c8c', token: 'invoice' },
	{ name: 'Indigo', hex: '#556acb', token: 'time' },
	{ name: 'Purple', hex: '#5b40bf', token: 'growth' },
	{ name: 'Pink', hex: '#923f4f', token: 'quote' }
] as const;
export function tagColor(color?: string | null) {
	return tagColors.find((entry) => entry.hex === color?.toLowerCase()) ?? tagColors[0];
}
export function nextTagColor(catalog: { color?: string | null }[]) {
	return (
		tagColors.find((entry) => !catalog.some((tag) => tag.color?.toLowerCase() === entry.hex)) ??
		tagColors[0]
	);
}
