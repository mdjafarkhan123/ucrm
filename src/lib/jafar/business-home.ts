import type { DealStage } from './deals';
import { DEAL_STAGE_LABELS, isoDate } from './deals';
import { jafarHomeKey } from './query-keys';
import { canUseJafarPath, type JafarViewer } from './team-access';

// Jafar business management C1: the Business Management home -- the "waiting on you" counts and the dated
// to-do list (overdue, today, the next seven days), in the words the page and the API share. HubSpot's Sales
// Workspace and Pipedrive's Activities set the shape: counts you tap to work through, then overdue first.

/** The list shows at most this many rows; the counts above it are always complete. */
export const HOME_AGENDA_LIMIT = 60;
/** "Next 7 days": tomorrow through a week from today. */
export const HOME_UPCOMING_DAYS = 7;

export type HomeAgendaItem = {
	id: string;
	business_name: string;
	country_code: string;
	trade: string;
	next_action: string;
	due_on: string;
	first_contact: boolean;
	/** The business's open Deal, if it has one. */
	deal_stage: DealStage | null;
	/** Set when the next action stands for a call: Done then asks how the call went. */
	call_id: string | null;
	/** D3b: whose step it is -- null is Jafar's -- shown on the whole team's list. */
	owner_member_id: string | null;
	owner_name: string | null;
};

/**
 * A count is null when it could not be worked out; the page then shows a dash rather than a wrong zero. D3b: the
 * Leads, Applications and first-contact counts are also null for a teammate who cannot open their list, and the
 * page leaves those tiles out.
 */
export type BusinessHome = {
	review: number | null;
	first_contact: number | null;
	accounts_to_create: number | null;
	setups_waiting: number | null;
	renewals: number | null;
	overdue: number;
	today: number;
	upcoming: number;
	items: HomeAgendaItem[];
};

export type HomeCount =
	'review' | 'first_contact' | 'accounts_to_create' | 'setups_waiting' | 'renewals';

/**
 * D3b: which "Waiting on you" counts this person may open, each judged by the request its list or action makes. The
 * server leaves the others out and the page hides their tiles. Jafar opens all of them.
 */
export function homeCountsOpen(viewer: JafarViewer): Record<HomeCount, boolean> {
	const can = (path: string, method?: string) => canUseJafarPath(viewer, path, method);
	return {
		review: can('/api/jafar/leads/x/approval', 'POST'),
		first_contact: can('/api/jafar/leads'),
		accounts_to_create: can('/api/jafar/prospects/x/provision', 'POST'),
		setups_waiting: can('/api/jafar/onboarding'),
		renewals: can('/api/jafar/organizations')
	};
}

export type HomeTag = { label: string; tone: 'informative' | 'success' | 'warning' | 'neutral' };

/** What kind of step a row is, from the step itself and the Deal it belongs to. */
export function agendaTag(
	item: Pick<HomeAgendaItem, 'first_contact' | 'deal_stage'> & { call_id?: string | null }
): HomeTag {
	if (item.first_contact) return { label: 'First contact', tone: 'success' };
	// A step that stands for a booked call is a call, whether or not the business has a Deal yet.
	if (item.call_id) return { label: 'Call', tone: 'informative' };
	switch (item.deal_stage) {
		case 'interested':
			return { label: 'Reply', tone: 'informative' };
		case 'call_booked':
			return { label: 'Call', tone: 'informative' };
		case 'pricing_shared':
		case 'awaiting_decision':
			return { label: 'Pricing', tone: 'warning' };
		case null:
		case undefined:
		case 'lost':
		case 'won':
			return { label: 'Follow-up', tone: 'neutral' };
		default:
			return { label: DEAL_STAGE_LABELS[item.deal_stage], tone: 'neutral' };
	}
}

export type AgendaGroup = { key: 'overdue' | 'today' | 'upcoming'; items: HomeAgendaItem[] };

/** The rows split by when they are due; the list already arrives earliest first. */
export function groupAgenda(items: HomeAgendaItem[], today: string): AgendaGroup[] {
	const groups: AgendaGroup[] = [
		{ key: 'overdue', items: [] },
		{ key: 'today', items: [] },
		{ key: 'upcoming', items: [] }
	];
	for (const item of items) {
		const group = item.due_on < today ? groups[0] : item.due_on === today ? groups[1] : groups[2];
		group.items.push(item);
	}
	return groups;
}

// --- Browser side -----------------------------------------------------------------------------------------------

/** Whose to-dos the home lists: the viewer's own, or (Jafar only) the whole team's. */
export type HomeScope = 'mine' | 'everyone';

export function businessHomeKey(today: string, scope: HomeScope = 'mine') {
	return [...jafarHomeKey, today, scope] as const;
}

export async function fetchBusinessHome(
	today: string = isoDate(new Date()),
	scope: HomeScope = 'mine'
): Promise<BusinessHome> {
	const everyone = scope === 'everyone' ? '&everyone=1' : '';
	const response = await fetch(`/api/jafar/home?today=${encodeURIComponent(today)}${everyone}`);
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'Your day could not be loaded.');
	return result as BusinessHome;
}
