import { sectionFacts, type SetupCatalogue } from '$lib/setup/catalogue';

// Jafar's list of paid clients going through setup (client onboarding C1, plan §8). The database works out
// each client's progress and whose move it is (supabase/migrations/20261006200000_client_onboarding_list.sql);
// this module is the one place that turns those codes into words.

export type OnboardingWaitingOn = 'client' | 'uplift' | 'nobody';
export type OnboardingNextAction =
	| 'start_setup'
	| 'finish_section'
	| 'send_to_uplift'
	| 'review_setup'
	| 'help_with_answers'
	| 'reply_to_support'
	| 'account_paused'
	| 'payment_reversed';
export const ONBOARDING_FILTERS = ['uplift', 'client', 'quiet'] as const;
export type OnboardingFilter = (typeof ONBOARDING_FILTERS)[number];

export type OnboardingClient = {
	id: string;
	name: string;
	lifecycle_status: string;
	package_name: string | null;
	account_created_at: string;
	payment_reversed: boolean;
	welcome_seen: boolean;
	sections_done: number;
	/** The tasks and questions this client is asked: everyone's, plus those of their package's services. */
	sections_total: number;
	facts_answered: number;
	facts_total: number;
	help_count: number;
	unread_support: number;
	next_section_key: string | null;
	/** The next section's title in the published setup version, added by the route. */
	next_section_title: string | null;
	/** C2: the newest Send to Uplift, if any. */
	sent_number: number | null;
	sent_at: string | null;
	waiting_on: OnboardingWaitingOn;
	next_action: OnboardingNextAction;
	last_activity_at: string;
	quiet: boolean;
};

export type OnboardingTotals = {
	all: number;
	uplift: number;
	client: number;
	quiet: number;
	matching: number;
};

export type OnboardingListPage = {
	clients: OnboardingClient[];
	next_cursor: string | null;
	totals: OnboardingTotals;
};

/**
 * The task list as the database needs it: each section's service, facts, which of them are required, and the
 * "show only if" rules of its conditional facts in order. The database keeps, for each client, only the
 * sections their package includes and the facts their answers and package leave asked.
 */
export function onboardingCatalogue(catalogue: SetupCatalogue) {
	return catalogue.sections.map((section) => {
		const facts = sectionFacts(section);
		return {
			key: section.key,
			service_key: section.serviceKey,
			facts: facts.map((fact) => fact.key),
			required: facts.filter((fact) => fact.required).map((fact) => fact.key),
			rules: facts.flatMap((fact) =>
				fact.showIf
					? [
							{
								fact_key: fact.key,
								show_if: fact.showIf.map((condition) =>
									'serviceKey' in condition
										? { service_key: condition.serviceKey }
										: 'hasRows' in condition
											? { fact_key: condition.factKey, has_rows: true }
											: { fact_key: condition.factKey, values: condition.values }
								)
							}
						]
					: []
			)
		};
	});
}

function plural(count: number, one: string, many: string) {
	return `${count} ${count === 1 ? one : many}`;
}

/** The next thing that has to happen for this client, in words. */
export function onboardingNextActionLabel(client: OnboardingClient): string {
	switch (client.next_action) {
		case 'reply_to_support':
			return `Reply to ${plural(client.unread_support, 'support chat', 'support chats')}`;
		case 'help_with_answers':
			return `Help with ${plural(client.help_count, 'answer', 'answers')}`;
		case 'start_setup':
			return 'Sign in and start setup';
		case 'finish_section':
			return `Finish ${client.next_section_title ?? 'setup'}`;
		case 'send_to_uplift':
			return 'Check answers and send to Uplift';
		case 'review_setup':
			return client.sent_number && client.sent_number > 1
				? 'Review their changed setup'
				: 'Review their setup';
		case 'account_paused':
			return 'Account paused — nothing to do until it is resumed';
		case 'payment_reversed':
			return 'Payment reversed — setup is on hold';
	}
}

/** Where the client stands, using the plan's client-facing project states (§5). */
export function onboardingStage(client: OnboardingClient): {
	label: string;
	tone: 'informative' | 'warning' | 'critical' | 'inactive';
} {
	if (client.payment_reversed) return { label: 'Payment reversed', tone: 'critical' };
	if (client.lifecycle_status !== 'active') return { label: 'Paused', tone: 'inactive' };
	if (client.sent_number) return { label: 'Uplift is reviewing', tone: 'informative' };
	if (!client.welcome_seen && client.facts_answered === 0)
		return { label: 'Not started', tone: 'warning' };
	return { label: 'Completing setup', tone: 'informative' };
}

export const onboardingWaitingOnLabel: Record<OnboardingWaitingOn, string> = {
	uplift: 'Uplift',
	client: 'Client',
	nobody: 'On hold'
};
