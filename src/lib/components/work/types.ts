// Shapes the shared work-object components pass between each other. A work object is a request, quote,
// job, or invoice — they draw the same header, the same client card, and the same facts column, so the
// props stay generic and every page hands in its own words.

/** One label/value row in the facts column beside the client card. */
export type RecordFact = {
	label: string;
	/** Leave empty and the row falls back to `empty`, or to a dash when that is absent too. */
	value?: string | null;
	/** What to say when there is no value yet, e.g. "Not booked yet". */
	empty?: string;
	/** Let a long value wrap instead of being clipped. Facts are dates and numbers that fit on one line, so
	 *  the row clips by default; set this for the few that carry a phrase somebody typed, like a payment
	 *  stage's name, where the clipped half is the half that identifies it. */
	wrap?: boolean;
	/** A Tabler icon (`?raw`) for the fact's tile in Classic. Omit and the list picks one from the label. */
	icon?: string;
	/** The tile's colour in Classic. Leave it out and the first fact carries the brand tint; `neutral`
	 *  keeps a tile plain, `brand` tints a later one (a request's booked assessment), and `waiting` marks a
	 *  fact still waiting on someone, like an unanswered quote. */
	tone?: 'neutral' | 'waiting' | 'brand';
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

/** A known record in the work journey. Unknown steps stay neutral, never implied complete. */
export type RecordLifecycleStep = {
	key: 'request' | 'quote' | 'job' | 'invoice' | 'paid';
	label: string;
	detail?: string;
	href?: string;
	current?: boolean;
	complete?: boolean;
};
