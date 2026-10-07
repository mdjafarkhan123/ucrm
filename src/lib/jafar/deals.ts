import type { QueryClient } from '@tanstack/svelte-query';
import type { OnboardingClient } from '$lib/setup/onboarding-list';
import { formatUsd } from './packages';
import { jafarDealsKey, jafarLeadKey, jafarLeadsKey } from './query-keys';

// Jafar business management B4: Uplift's sales Deals -- the words the board, the Deal box on a business's page,
// and the API share. A Deal is one buying conversation with a business; its next step is the business's one next
// action. B5: a Deal becomes Won by itself when payment is confirmed on the Application linked to it.

export const OPEN_DEAL_STAGES = [
	'interested',
	'call_booked',
	'needs_understood',
	'pricing_shared',
	'awaiting_decision',
	'later'
] as const;
export type OpenDealStage = (typeof OPEN_DEAL_STAGES)[number];
/** Lost and Won are closed: off the board, behind their own buttons. Nobody moves a Deal to Won by hand. */
export type ClosedDealStage = 'lost' | 'won';
export type DealStage = OpenDealStage | ClosedDealStage;

export const DEAL_STAGE_LABELS: Record<DealStage, string> = {
	interested: 'Interested',
	call_booked: 'Call booked',
	needs_understood: 'Needs understood',
	pricing_shared: 'Pricing shared',
	awaiting_decision: 'Awaiting decision',
	later: 'Later',
	lost: 'Lost',
	won: 'Won'
};

/** What each column holds, under its title on an empty board. */
export const DEAL_STAGE_HINTS: Record<OpenDealStage, string> = {
	interested: 'They replied and want to know more.',
	call_booked: 'A call is in the diary.',
	needs_understood: 'You know what they need.',
	pricing_shared: 'They have the pricing link.',
	awaiting_decision: 'Waiting for their yes and payment.',
	later: 'They asked you to come back on a date.'
};

/** A Deal starts here (Jafar, B4 Q8). */
export const DEAL_START_STAGES = ['interested', 'call_booked'] as const;
export type DealStartStage = (typeof DEAL_START_STAGES)[number];

/** Moving into these asks for a date: the call, when to revisit, when to follow up (B4 Q10). */
export const STAGES_NEEDING_DATE: readonly OpenDealStage[] = [
	'call_booked',
	'awaiting_decision',
	'later'
];

export const LOST_REASONS = [
	'price',
	'chose_other',
	'timing',
	'no_response',
	'not_a_fit',
	'other'
] as const;
export type LostReasonChoice = (typeof LOST_REASONS)[number];
/** Set only when a business asks not to be contacted. */
export type LostReason = LostReasonChoice | 'asked_not_to_contact';

export const LOST_REASON_LABELS: Record<LostReason, string> = {
	price: 'Price too high',
	chose_other: 'Chose someone else',
	timing: 'Not the right time',
	no_response: 'Stopped replying',
	not_a_fit: 'Not a good fit',
	other: 'Other',
	asked_not_to_contact: 'Asked not to be contacted'
};

export const DEAL_NOTE_MAX = 1000;
export const DEAL_BOARD_PAGE_SIZE = 30;
export const SHARED_PACKAGES_MAX = 5;
/** Following up two or three days after sending a price is common practice (B4 Q4). */
export const PRICING_FOLLOW_UP_DAYS = 3;

/** The prefilled wording and date for each move; Jafar can change both. */
export function suggestedNextStep(
	stage: OpenDealStage,
	businessName: string,
	today: Date = new Date()
): { text: string; due_on: string } {
	const plus = (days: number) => isoDate(addDays(today, days));
	switch (stage) {
		case 'interested':
			return { text: `Reply to ${businessName}`, due_on: plus(0) };
		case 'call_booked':
			return { text: `Call with ${businessName}`, due_on: plus(1) };
		case 'needs_understood':
			return { text: `Share pricing with ${businessName}`, due_on: plus(1) };
		case 'pricing_shared':
			return {
				text: `Follow up on pricing with ${businessName}`,
				due_on: plus(PRICING_FOLLOW_UP_DAYS)
			};
		case 'awaiting_decision':
			return { text: `Check ${businessName}'s decision`, due_on: plus(3) };
		case 'later':
			return { text: `Check back with ${businessName}`, due_on: plus(30) };
	}
}

function addDays(date: Date, days: number) {
	const next = new Date(date);
	next.setDate(next.getDate() + days);
	return next;
}

/** The local calendar date, "2026-10-07". */
export function isoDate(date: Date) {
	const month = String(date.getMonth() + 1).padStart(2, '0');
	const day = String(date.getDate()).padStart(2, '0');
	return `${date.getFullYear()}-${month}-${day}`;
}

/** "$129/mo" for a column total or a card. */
export function monthlyValue(cents: number | null) {
	return cents === null ? null : `${formatUsd(cents)}/mo`;
}

export type DealCard = {
	id: string;
	relationship_id: string;
	business_name: string;
	country_code: string;
	trade: string;
	contact_name: string | null;
	stage: DealStage;
	stage_entered_at: string;
	value_monthly_usd_cents: number | null;
	/** The packages in the latest share, main one first. */
	shared_packages: string[];
	has_agreed_terms: boolean;
	next_action: string | null;
	next_action_due_on: string | null;
	lost_reason: LostReason | null;
	lost_at: string | null;
	/** B5: when payment won it, whether that payment was later reversed, and the package paid for. */
	won_at: string | null;
	payment_reversed: boolean;
	won_package_name: string | null;
};

export type DealColumnPage = { deals: DealCard[]; next_cursor: string | null };

export type DealBoardSummary = {
	columns: Partial<Record<OpenDealStage, { count: number; value_monthly_usd_cents: number }>>;
	lost: number;
	won: number;
};

/** One package as it was shared -- the copy the business saw, kept whatever happens to prices later. */
export type DealPriceShare = {
	shared_at: string;
	package_slug: string;
	package_name: string;
	monthly_price_usd_cents: number | null;
	yearly_price_usd_cents: number | null;
	offers: Record<string, { name: string; intro_price_usd_cents: number; periods: number } | null>;
	link: string;
	actor_email: string;
};

export type BusinessDeal = {
	id: string;
	stage: DealStage;
	stage_entered_at: string;
	value_monthly_usd_cents: number | null;
	agreed_terms: string | null;
	agreed_terms_by_email: string | null;
	agreed_terms_at: string | null;
	lost_reason: LostReason | null;
	lost_note: string | null;
	lost_from_stage: OpenDealStage | null;
	lost_at: string | null;
	/** B5: who confirmed the payment that won it, and on which Application. */
	won_at: string | null;
	won_by_email: string | null;
	won_application_id: string | null;
	created_at: string;
	/** Newest share first; one share's packages keep the order they were chosen in. */
	shares: DealPriceShare[];
};

/** B5: a teammate who can look after a new client's setup. */
export type SetupOwnerChoice = { id: string; name: string; avatar_url: string | null };

/**
 * B5: the Client box on a business's page, from its newest Won Deal: the paid Application and its payments, the
 * account made from it, who looks after setup (null is Jafar), and where onboarding stands. Each part the
 * viewer's access does not open comes back null or empty.
 */
export type BusinessClient = {
	deal_id: string;
	won_at: string;
	won_by_email: string;
	application: {
		id: string;
		stage: string;
		package_name: string | null;
		billing_interval: 'month' | 'year' | null;
		monthly_price_usd_cents: number | null;
		yearly_price_usd_cents: number | null;
		payment_reversed_at: string | null;
	} | null;
	payments: {
		id: string;
		amount_usd_cents: number;
		received_on: string;
		/** Free text as Jafar typed it ("Wise"); may be empty. */
		method: string | null;
		reversed_at: string | null;
	}[];
	account: {
		status: string;
		organization_id: string | null;
		organization_name: string | null;
		lifecycle_status: string | null;
	} | null;
	setup_owner: SetupOwnerChoice | null;
	/** The business's row on the onboarding list, once its account exists. */
	onboarding: OnboardingClient | null;
};

/** Today's local date compared with a due date: overdue only once the day has passed. */
export function isOverdue(dueOn: string | null, today: string = isoDate(new Date())) {
	return dueOn !== null && dueOn < today;
}

/** Whole days since a moment, for "9 days" on a card. */
export function daysSince(isoMoment: string, now: Date = new Date()) {
	return Math.max(0, Math.floor((now.getTime() - new Date(isoMoment).getTime()) / 86_400_000));
}

/** The most recent share's packages: everything shared at the newest moment. */
export function latestShare(deal: Pick<BusinessDeal, 'shares'>) {
	const newest = deal.shares[0]?.shared_at;
	return newest ? deal.shares.filter((share) => share.shared_at === newest) : [];
}

// --- Browser side -----------------------------------------------------------------------------------------------

export function dealColumnKey(stage: DealStage) {
	return [...jafarDealsKey, 'column', stage] as const;
}

export const dealSummaryKey = [...jafarDealsKey, 'summary'] as const;
/** The packages on the pricing page, for "Pricing shared"; warmed when the button is hovered. */
export const dealPackagesKey = [...jafarDealsKey, 'packages'] as const;

export type ShareablePackage = {
	slug: string;
	name: string;
	monthly_price_usd_cents: number | null;
	yearly_price_usd_cents: number | null;
};

export async function fetchDealPackages() {
	const response = await fetch('/api/jafar/deals/packages');
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'The packages could not be loaded.');
	return result.packages as ShareablePackage[];
}

export function prefetchDealPackages(queryClient: QueryClient) {
	return queryClient.prefetchQuery({
		queryKey: dealPackagesKey,
		queryFn: fetchDealPackages,
		staleTime: 60_000
	});
}

export async function fetchDealColumn(stage: DealStage, cursor: string | null) {
	const params = new URLSearchParams({ stage });
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(`/api/jafar/deals?${params}`);
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'These Deals could not be loaded.');
	return result as DealColumnPage;
}

export async function fetchDealSummary() {
	const response = await fetch('/api/jafar/deals/summary');
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'The board could not be loaded.');
	return result as DealBoardSummary;
}

/** After any Deal change: the board, the business's page, and the Leads list (a Deal moves a business off it). */
export function refreshDeals(queryClient: QueryClient, relationshipId: string) {
	return Promise.all([
		queryClient.invalidateQueries({ queryKey: jafarDealsKey }),
		queryClient.invalidateQueries({ queryKey: jafarLeadKey(relationshipId) }),
		queryClient.invalidateQueries({ queryKey: [...jafarLeadsKey, 'list'] })
	]);
}
