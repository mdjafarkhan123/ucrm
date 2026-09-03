import type { ClientListItem } from '$lib/clients/api';

// The bridge between Schedule's compact "new Job" form and the full New Job page. When someone building a
// job from empty calendar space presses More Options, whatever they have typed so far is staged here and the
// page reads it once on the way in, so the full form opens already filled instead of blank. It never touches
// the URL -- the client row and its property need to survive the hop, and those do not belong in a query
// string.

/** The first visit's schedule and team, seeded by the calendar gesture that opened the create form. */
export type JobFirstVisitSeed = {
	visit_date: string | null;
	start_time: string | null;
	end_time: string | null;
	all_day: boolean;
	assignee_ids: string[];
	instructions: string | null;
};

/** A partly-built Job handed from Schedule to the full New Job page. The client row travels whole so the
 *  property picker there has the primary property and the count it needs, not just an id. */
export type JobCreateSeed = {
	client: ClientListItem | null;
	property_id: string;
	title: string;
	first_visit: JobFirstVisitSeed | null;
};

let pending: JobCreateSeed | null = null;

/** Hold a draft for the next New Job page load. */
export function stageJobCreateSeed(seed: JobCreateSeed) {
	pending = seed;
}

/** Read the staged draft and clear it, so it seeds exactly one page load and a later plain visit is blank. */
export function takeJobCreateSeed(): JobCreateSeed | null {
	const seed = pending;
	pending = null;
	return seed;
}
