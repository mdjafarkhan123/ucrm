// Client onboarding E1: the client-facing project states (plan §5) and the step tracker built from them. Industry
// reference: parcel and order trackers (Shopify's order status page) and client portals such as GuideCX and
// Rocketlane — every step in order, finished steps ticked with the day they happened, the current one marked,
// and the promised range on the step it leads to. The state is worked out from the records each stage keeps, never
// stored, so it cannot drift from them.
//
// Jafar's choices of 2026-10-05: "Ready for Uplift" turns into "Building your system" by itself on the first
// business day after Ready; once Ready is recorded the tracker stays on Building while the client sends changes
// or Uplift sends a task back, with a note saying so. Payment and verification happen before the account exists,
// so the client only ever sees them done. E3 adds Ready for your review: Jafar has released a preview. E4 adds
// Approved — preparing launch: the final approver approved the newest preview. E6 adds Live — training next (Jafar
// marked the approved system live) and Project delivered (Jafar closed delivery); both are final.

import type { PreviewFacts } from '$lib/setup/preview';
import { addBusinessDays } from '$lib/setup/ready';

export const PROJECT_STATES = [
	'payment_required',
	'payment_verifying',
	'complete_setup',
	'uplift_reviewing',
	'waiting_for_information',
	'ready_for_uplift',
	'building',
	'ready_for_review',
	'approved',
	'live',
	'delivered'
] as const;
export type ProjectState = (typeof PROJECT_STATES)[number];

/** The plan's wording, as the client reads it. */
export const PROJECT_STATE_LABEL: Record<ProjectState, string> = {
	payment_required: 'Payment required',
	payment_verifying: 'Payment being verified',
	complete_setup: 'Complete your setup',
	uplift_reviewing: 'Uplift is reviewing',
	waiting_for_information: 'Waiting for your information',
	ready_for_uplift: 'Ready for Uplift',
	building: 'Building your system',
	ready_for_review: 'Ready for your review',
	approved: 'Approved — preparing launch',
	live: 'Live — training next',
	delivered: 'Project delivered'
};

/** The same states as Jafar reads them about a client. */
export const PROJECT_STATE_OWNER_LABEL: Record<ProjectState, string> = {
	...PROJECT_STATE_LABEL,
	complete_setup: 'Completing setup',
	waiting_for_information: 'Waiting for their information',
	building: 'Building their system',
	ready_for_review: 'Ready for their review'
};

/** What a client's records say, as both the client's page and Jafar's list read them. */
export type ProjectFacts = {
	/** When the account was created, which happens once Jafar has confirmed the payment. */
	paid_at: string | null;
	/** The first and the newest Send to Uplift. */
	first_sent_at: string | null;
	sent: { number: number; submitted_at: string } | null;
	/** Tasks Uplift sent back on the newest send. */
	returned_count: number;
	/** Ready for Uplift, with the client's own dates (`YYYY-MM-DD`). */
	ready: {
		submission_number: number;
		start_date: string;
		target_from: string;
		target_to: string;
	} | null;
	/** E3: the newest preview Jafar released, after Ready. */
	preview: PreviewFacts | null;
	/** E4: the standing launch approval, on the newest preview; a newer release replaces it. */
	approval: { version: number; approved_at: string } | null;
	/** E6: when Jafar marked the system live and the project delivered. */
	handover: { live_at: string | null; delivered_at: string | null } | null;
	/** Today in the client's time zone, `YYYY-MM-DD`. */
	today: string;
};

/** The first business day of the build: the one after Ready was recorded. */
export const buildStartDate = (startDate: string) => addBusinessDays(startDate, 1);

/** Where the project stands now. */
export function projectState(facts: ProjectFacts): ProjectState {
	if (facts.handover?.delivered_at) return 'delivered';
	if (facts.handover?.live_at) return 'live';
	if (facts.ready && facts.preview && facts.approval) return 'approved';
	if (facts.ready && facts.preview) return 'ready_for_review';
	if (facts.ready)
		return facts.today >= buildStartDate(facts.ready.start_date) ? 'building' : 'ready_for_uplift';
	if (facts.sent && facts.returned_count > 0) return 'waiting_for_information';
	if (facts.sent) return 'uplift_reviewing';
	return 'complete_setup';
}

export type ProjectStepStatus = 'done' | 'current' | 'upcoming';
export type ProjectStep = {
	state: ProjectState;
	status: ProjectStepStatus;
	/** The day it happened or starts (`YYYY-MM-DD`, or a timestamp for the moments the client did something). */
	on: string | null;
	/** The promised range, on the step the build leads to. */
	range: { from: string; to: string } | null;
};

export type ProjectView = {
	state: ProjectState;
	/** The current step's place among the steps shown, counted from 1, and how many are shown. */
	position: number;
	total: number;
	steps: ProjectStep[];
	/**
	 * After Ready, what is happening with a send after it: tasks sent back, or changes Uplift is looking at. On
	 * the review step, whether the client has sent their notes on the newest preview (E3).
	 */
	after_ready:
		| { kind: 'returned'; count: number }
		| { kind: 'changes_sent' }
		| { kind: 'notes_sent'; at: string }
		| null;
};

/**
 * The tracker. "Waiting for your information" is shown only while it is the current step — like a parcel
 * tracker's delivery problem, it is a detour, not a stop every project makes.
 */
export function projectView(facts: ProjectFacts): ProjectView {
	const state = projectState(facts);
	const currentIndex = PROJECT_STATES.indexOf(state);
	const shown = PROJECT_STATES.filter(
		(step) => step !== 'waiting_for_information' || state === 'waiting_for_information'
	);

	const on: Partial<Record<ProjectState, string | null>> = {
		payment_verifying: facts.paid_at,
		complete_setup: facts.first_sent_at,
		uplift_reviewing: state === 'uplift_reviewing' ? (facts.sent?.submitted_at ?? null) : null,
		ready_for_uplift: facts.ready?.start_date ?? null,
		building: facts.ready ? buildStartDate(facts.ready.start_date) : null,
		ready_for_review: facts.ready ? (facts.preview?.released_at ?? null) : null,
		approved: facts.ready && facts.preview ? (facts.approval?.approved_at ?? null) : null,
		live: facts.handover?.live_at ?? null,
		delivered: facts.handover?.delivered_at ?? null
	};

	const steps = shown.map((step): ProjectStep => {
		const index = PROJECT_STATES.indexOf(step);
		return {
			state: step,
			status: index < currentIndex ? 'done' : index === currentIndex ? 'current' : 'upcoming',
			on: on[step] ?? null,
			range:
				step === 'ready_for_review' && facts.ready
					? { from: facts.ready.target_from, to: facts.ready.target_to }
					: null
		};
	});

	let afterReady: ProjectView['after_ready'] = null;
	if (state === 'ready_for_review' && facts.preview?.notes_sent_at)
		afterReady = { kind: 'notes_sent', at: facts.preview.notes_sent_at };
	else if (facts.ready && facts.sent && facts.sent.number > facts.ready.submission_number)
		afterReady =
			facts.returned_count > 0
				? { kind: 'returned', count: facts.returned_count }
				: { kind: 'changes_sent' };

	return {
		state,
		position: shown.indexOf(state) + 1,
		total: shown.length,
		steps,
		after_ready: afterReady
	};
}
