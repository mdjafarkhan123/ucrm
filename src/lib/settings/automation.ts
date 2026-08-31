// Settings → Automation (Part 6B shell). The contractor-facing read of the one server access decision in
// $lib/server/access/automation.ts. The page renders whatever this returns and never reconstructs
// entitlement, permission, authority, or limits on its own. In 6B there is no recipe data — only the
// access shell, kept unreachable from the Settings home until 6D provides a real recipe journey.

export type AutomationLimitState = 'unlimited' | 'not_included' | 'numeric';

export type AutomationLimit = {
	state: AutomationLimitState;
	value: number | null;
	is_unlimited: boolean;
	source: 'package' | 'override';
};

export const AUTOMATION_LIMIT_KEYS = [
	'automation_active_recipes',
	'automation_max_conditions_per_recipe',
	'automation_max_steps_per_recipe',
	'automation_max_customer_messages_per_enrollment',
	'automation_min_customer_message_spacing_minutes',
	'automation_max_delay_days',
	'automation_max_enrollment_duration_days'
] as const;
export type AutomationLimitKey = (typeof AUTOMATION_LIMIT_KEYS)[number];

export type AutomationAuthorityState = 'enabled' | 'operationally_disabled' | 'security_suspended';

export type AutomationAccessView = {
	organization_id: string;
	included: boolean;
	authority_state: AutomationAuthorityState;
	authority_reason: string | null;
	read_only: boolean;
	can_view: boolean;
	can_manage: boolean;
	can_activate: boolean;
	can_control_enrollment: boolean;
	limits: Record<AutomationLimitKey, AutomationLimit>;
	allowed_actions: string[];
};

// A direct visit to the destination is an honest denial, not a crash: a contractor whose plan excludes
// Automation, or who lacks view permission, gets a specific shell rather than an error or an empty list.
// Only a real fault (network, 500) throws, so the query's error path stays reserved for retryable trouble.
export type AutomationAccessResult =
	| { status: 'ok'; access: AutomationAccessView }
	| { status: 'denied'; reason: 'not_included' | 'permission_denied' };

export const automationSettingsKey = ['settings', 'automation'] as const;

export async function fetchAutomationSettings(): Promise<AutomationAccessResult> {
	const response = await fetch('/api/settings/automation');
	if (response.ok) {
		return { status: 'ok', access: (await response.json()) as AutomationAccessView };
	}
	if (response.status === 403) {
		const body = (await response.json().catch(() => ({}))) as { reason?: string };
		return {
			status: 'denied',
			reason: body.reason === 'not_included' ? 'not_included' : 'permission_denied'
		};
	}
	throw new Error('Automation could not be loaded.');
}
