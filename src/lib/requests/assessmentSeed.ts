// The bridge between Schedule's empty-slot chooser and the full New Request page. When someone clicks empty
// calendar space and picks Request instead of Job, the slot's day, time and Anytime are staged here and the
// New Request page reads them once on the way in, so its on-site assessment opens already booked onto that
// slot. It never touches the URL -- these are the same date-only day and wall-clock the calendar drew, and
// they do not belong in a query string. The Request and its assessment are still created and owned by
// Requests; Schedule only hands over the slot the person pointed at.

/** The slot a calendar gesture proposed, in the calendar's own shape: an organization-timezone day and clock
 *  with no UTC conversion. A null day means the person opened the chooser without a slot (the header action),
 *  so the New Request page opens without pre-booking a visit. */
export type AssessmentCreateSeed = {
	visit_date: string | null;
	/** As the calendar draws it, 'HH:MM'. Null for an Anytime or dateless slot. */
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
};

let pending: AssessmentCreateSeed | null = null;

/** Hold a slot for the next New Request page load. */
export function stageAssessmentSeed(seed: AssessmentCreateSeed) {
	pending = seed;
}

/** Read the staged slot and clear it, so it seeds exactly one page load and a later plain New Request is
 *  blank. */
export function takeAssessmentSeed(): AssessmentCreateSeed | null {
	const seed = pending;
	pending = null;
	return seed;
}
