// How the board writes money and follow-up dates, in one place, so a card, a column heading and the
// brief can never disagree.
//
// The rule that matters: a missing estimate is nothing at all. It is never a zero, never a dash dressed
// up as money, and never counted into a total. A real zero someone typed is still shown as zero.

export type BoardFormatting = {
	currency_code: string;
	locale: string;
	timezone: string;
};

export function formatMoney(value: number | null | undefined, formatting: BoardFormatting) {
	if (value === null || value === undefined) return null;
	return new Intl.NumberFormat(formatting.locale, {
		style: 'currency',
		currency: formatting.currency_code,
		// Whole amounts read better on a dense board; anything with cents keeps them.
		minimumFractionDigits: Number.isInteger(value) ? 0 : 2,
		maximumFractionDigits: 2
	}).format(value);
}

// Today where the business is, not where the browser is. A follow-up set for the 25th is overdue on the
// 26th in the contractor's own calendar, whatever timezone the person looking at it happens to be in.
export function todayInOrganization(formatting: BoardFormatting, now: Date = new Date()) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: formatting.timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(now);
}

export type FollowUp = {
	/** `Aug 25`, or `Aug 25, 2027` once it leaves this year. */
	label: string;
	overdue: boolean;
	/** Said in full, so the red is never the only thing carrying the meaning. */
	description: string;
};

export function followUp(
	date: string | null | undefined,
	formatting: BoardFormatting,
	now: Date = new Date()
): FollowUp | null {
	if (!date) return null;

	const today = todayInOrganization(formatting, now);
	const overdue = date < today;
	// A plain date string has no time and no zone, so it is read as one rather than shifted by the
	// browser's offset — otherwise the 25th shows as the 24th west of UTC.
	const [year, month, day] = date.split('-').map(Number);
	const parsed = new Date(year, (month ?? 1) - 1, day ?? 1);
	const sameYear = String(year) === today.slice(0, 4);

	const label = parsed.toLocaleDateString(formatting.locale, {
		month: 'short',
		day: 'numeric',
		...(sameYear ? {} : { year: 'numeric' })
	});

	return {
		label,
		overdue,
		description: overdue ? `Follow-up overdue since ${label}` : `Follow up on ${label}`
	};
}
