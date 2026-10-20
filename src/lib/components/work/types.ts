// Shapes the shared work-object components pass between each other. A work object is a request, quote,
// job, or invoice — they draw the same header, the same client card, and the same facts column, so the
// props stay generic and every page hands in its own words.

/** One label/value row in the facts column beside the client card. */
export type RecordFact = {
	label: string;
	/** Leave empty and the fact falls back to `empty`, or to a dash when that is absent too. */
	value?: string | null;
	/** What to say when there is no value yet, in honest words, e.g. "Waiting for an answer". */
	empty?: string;
	/** Tabler icon (`?raw`) drawn on the small tile beside the label. */
	icon?: string;
	/** The record or part of the app this fact belongs to; its colour tints the icon tile. */
	kind?: 'job' | 'time' | 'quote' | 'client' | 'conversation' | 'request' | 'invoice' | 'warning';
	/** Draw the value in the quiet colour, for a fact still waiting on something. */
	quiet?: boolean;
	/** Makes the value a link, e.g. `tel:` or `mailto:`. */
	href?: string;
};

/** One address slot on the client summary card. A quote shows only the property; an invoice shows the
 *  billing address above it. */
export type SummaryAddress = {
	/** Shown above the address when the card carries more than one, e.g. "Billing address". */
	label?: string;
	/** The address on one line, or null when there is none to show. */
	value: string | null;
	/** What to say when `value` is null, e.g. "No property on this request". */
	empty?: string;
};

/** The five tones the design system supports. Mapping a record's own statuses onto them belongs to the
 *  page, not to the shared header. */
export type StatusTone = 'success' | 'critical' | 'warning' | 'informative' | 'inactive';

/** One line on the Overview card above a work list: a status, how many are in it, and its tone. */
export type StatusOverviewRow = {
	label: string;
	count: number;
	tone: StatusTone;
};
