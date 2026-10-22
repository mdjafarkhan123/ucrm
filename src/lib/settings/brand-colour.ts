// The Branding page's colour rules: the quick picks, what counts as a colour code, and whether white words
// stay easy to read on the chosen colour (the check behind the notice under the picks).

export const DEFAULT_BRAND_COLOUR = '#2c5cc5';

export const BRAND_QUICK_PICKS = [
	'#0f766e',
	'#15803d',
	'#2c5cc5',
	'#6d3fc6',
	'#c2410c',
	'#b91c1c',
	'#0e7490',
	'#1e293b'
] as const;

/** "#0F766E", "0f766e" or "#0f6" as the lower-case "#rrggbb" the server stores, or null when it is not a colour. */
export function normaliseColourCode(input: string): string | null {
	const code = input.trim().replace(/^#/, '').toLowerCase();
	if (/^[0-9a-f]{3}$/.test(code)) {
		return `#${[...code].map((digit) => digit + digit).join('')}`;
	}
	return /^[0-9a-f]{6}$/.test(code) ? `#${code}` : null;
}

function channel(value: number): number {
	const unit = value / 255;
	return unit <= 0.03928 ? unit / 12.92 : ((unit + 0.055) / 1.055) ** 2.4;
}

/** The WCAG contrast of white words on this "#rrggbb" colour: 1 (invisible) to 21 (black). */
export function whiteContrast(colour: string): number {
	const red = parseInt(colour.slice(1, 3), 16);
	const green = parseInt(colour.slice(3, 5), 16);
	const blue = parseInt(colour.slice(5, 7), 16);
	const luminance = 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue);
	return 1.05 / (luminance + 0.05);
}

/** Buttons and headers on a customer page carry white words, so the colour has to hold them (WCAG AA, 4.5). */
export function readsClearlyWithWhite(colour: string): boolean {
	return whiteContrast(colour) >= 4.5;
}
