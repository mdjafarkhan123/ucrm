// How the Business profile page words the regional facts: the time zone in plain English, the time there
// right now, and what an amount and a date look like once the business's currency and zone are applied.

/** "Vancouver · Pacific Time (UTC−7)" for "America/Vancouver". */
export function timezoneLabel(timezone: string, at: Date = new Date()): string {
	try {
		const long =
			new Intl.DateTimeFormat('en', { timeZone: timezone, timeZoneName: 'long' })
				.formatToParts(at)
				.find((part) => part.type === 'timeZoneName')?.value ?? timezone;
		const offset =
			new Intl.DateTimeFormat('en', { timeZone: timezone, timeZoneName: 'shortOffset' })
				.formatToParts(at)
				.find((part) => part.type === 'timeZoneName')?.value ?? '';
		const city = (timezone.split('/').pop() ?? timezone).replaceAll('_', ' ');
		const utc = offset === 'GMT' ? 'UTC' : offset.replace('GMT', 'UTC').replace('-', '−');
		return `${city} · ${long} (${utc})`;
	} catch {
		return timezone;
	}
}

/** "8:41 PM · Thursday, Oct 22" in the given zone, or an empty string when the zone is not known. */
export function timeThere(timezone: string, at: Date = new Date()): string {
	try {
		const time = new Intl.DateTimeFormat('en', {
			timeZone: timezone,
			hour: 'numeric',
			minute: '2-digit'
		}).format(at);
		const day = new Intl.DateTimeFormat('en', {
			timeZone: timezone,
			weekday: 'long',
			month: 'short',
			day: 'numeric'
		}).format(at);
		return `${time} · ${day}`;
	} catch {
		return '';
	}
}

/** "$1,250.00 · Oct 22, 2026": the sample amount and date a customer would read on a quote. */
export function amountAndDateSample(
	currency: string,
	timezone: string,
	locale = 'en',
	at: Date = new Date()
): string {
	try {
		const amount = new Intl.NumberFormat(locale, { style: 'currency', currency }).format(1250);
		const date = new Intl.DateTimeFormat(locale, {
			timeZone: timezone,
			dateStyle: 'medium'
		}).format(at);
		return `${amount} · ${date}`;
	} catch {
		return '';
	}
}
