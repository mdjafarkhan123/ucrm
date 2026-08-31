import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import {
	OrganizationAccessNotFoundError,
	resolveOrganizationAccess,
	type AccessClient,
	type EffectiveOrganizationAccess
} from '$lib/server/access/effective';

// Part 6B: the single server decision boundary for Automation. Every later Automation route, command,
// Settings navigation gate, and record-level control consumes this module; none reconstructs entitlement,
// permission, authority, or limits on its own. It fails closed on every uncertain state.

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

export type AutomationLimit = {
	state: 'unlimited' | 'not_included' | 'numeric';
	value: number | null;
	is_unlimited: boolean;
	source: 'package' | 'override';
};

// Two platform-controlled axes collapse to one effective state: a security suspension outranks an
// operational disable, which outranks the healthy default.
export type AutomationAuthorityState = 'enabled' | 'operationally_disabled' | 'security_suspended';

export const AUTOMATION_CAPABILITIES = [
	'view',
	'manage',
	'activate',
	'control_enrollment'
] as const;
export type AutomationCapability = (typeof AUTOMATION_CAPABILITIES)[number];

export type AutomationAccess = {
	organization_id: string;
	// The plan includes Automation (feature `automations` is effective).
	included: boolean;
	authority_state: AutomationAuthorityState;
	// Safe reason for the currently effective blocking axis, shown to a suspended/disabled viewer.
	authority_reason: string | null;
	// Has view but every write is blocked by authority.
	read_only: boolean;
	can_view: boolean;
	can_manage: boolean;
	can_activate: boolean;
	can_control_enrollment: boolean;
	// Non-null only when the destination itself is unreachable (no view). A viewer whose writes are blocked
	// by authority is read_only rather than denied, and keeps read access to history.
	denial_reason: 'not_included' | 'permission_denied' | null;
	limits: Record<AutomationLimitKey, AutomationLimit>;
	// Explicit action allowlist. Empty in 6B; dependency-ready catalog entries populate it in a later slice.
	allowed_actions: string[];
};

function notIncludedLimit(): AutomationLimit {
	return { state: 'not_included', value: null, is_unlimited: false, source: 'package' };
}

function buildAutomationLimits(
	rows: Array<{
		limit_key: string;
		state: string;
		value: number | null;
		is_unlimited: boolean;
		source: string;
	}>
): Record<AutomationLimitKey, AutomationLimit> {
	const byKey = new Map(rows.map((row) => [row.limit_key, row]));
	return Object.fromEntries(
		AUTOMATION_LIMIT_KEYS.map((key) => {
			const row = byKey.get(key);
			if (!row) return [key, notIncludedLimit()];
			const state = row.state as AutomationLimit['state'];
			return [
				key,
				{
					state,
					value: state === 'numeric' ? row.value : null,
					is_unlimited: row.is_unlimited,
					source: row.source === 'override' ? 'override' : 'package'
				}
			];
		})
	) as Record<AutomationLimitKey, AutomationLimit>;
}

// Resolve the full Automation access decision for one organization. Reuses the general access resolver
// for the plan feature and the caller's permissions; a caller that already resolved it can pass it in to
// avoid a second round trip. The seven limits and the authority projection are read in one pass each, both
// tenant-scoped by RLS so naming another organization returns nothing and fails closed.
export async function resolveAutomationAccess(
	client: AccessClient,
	organizationId: string,
	userId?: string,
	preresolvedAccess?: EffectiveOrganizationAccess
): Promise<AutomationAccess> {
	const access =
		preresolvedAccess ?? (await resolveOrganizationAccess(client, organizationId, userId));

	const [limitsResult, authorityResult] = await Promise.all([
		client.rpc('effective_automation_limits', { target_organization_id: organizationId }),
		client
			.from('organization_automation_authority')
			.select('operational_state, security_state, operational_reason, security_reason')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);
	if (limitsResult.error) throw limitsResult.error;
	if (authorityResult.error) throw authorityResult.error;

	const limits = buildAutomationLimits(limitsResult.data ?? []);

	const authority = authorityResult.data;
	const securitySuspended = authority?.security_state === 'suspended';
	const operationallyDisabled = authority?.operational_state === 'disabled';
	const authorityState: AutomationAuthorityState = securitySuspended
		? 'security_suspended'
		: operationallyDisabled
			? 'operationally_disabled'
			: 'enabled';
	const authorityReason = securitySuspended
		? (authority?.security_reason ?? null)
		: operationallyDisabled
			? (authority?.operational_reason ?? null)
			: null;
	const writesBlocked = authorityState !== 'enabled';

	// `access.permissions` already folds the plan entitlement in, so an off feature yields false here; the
	// explicit `included` check keeps the denial reasons unambiguous.
	const included = access.features['automations'] === true;
	const canView = included && access.permissions['automations.view'] === true;
	const canManage = included && !writesBlocked && access.permissions['automations.manage'] === true;
	const canActivate =
		included && !writesBlocked && access.permissions['automations.activate'] === true;
	const canControlEnrollment =
		included && !writesBlocked && access.permissions['automations.control_enrollment'] === true;

	return {
		organization_id: organizationId,
		included,
		authority_state: authorityState,
		authority_reason: authorityReason,
		read_only: canView && writesBlocked,
		can_view: canView,
		can_manage: canManage,
		can_activate: canActivate,
		can_control_enrollment: canControlEnrollment,
		denial_reason: !included ? 'not_included' : !canView ? 'permission_denied' : null,
		limits,
		allowed_actions: []
	};
}

export type AutomationAccessCheck =
	| { auth: OrganizationContext; access: EffectiveOrganizationAccess; automation: AutomationAccess }
	| { response: Response };

// The gate every Automation route calls first. It resolves access once, then translates the decision into
// the same honest, non-leaking refusals the rest of the app uses: not part of your plan, not allowed,
// temporarily unavailable, or suspended -- never an empty list or a database error, and never a signal
// that a resource exists in another tenant.
export async function requireAutomationAccess(
	event: RequestEvent,
	capability: AutomationCapability
): Promise<AutomationAccessCheck> {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return {
			response: json(
				{ error: 'Authentication or organization membership required.' },
				{ status: 401 }
			)
		};
	}

	try {
		const access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
		const automation = await resolveAutomationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id,
			access
		);

		if (!automation.included) {
			return {
				response: json(
					{ error: 'Automation is not part of your current plan.', reason: 'not_included' },
					{ status: 403 }
				)
			};
		}
		if (!automation.can_view) {
			return {
				response: json(
					{ error: 'You do not have access to automations.', reason: 'permission_denied' },
					{ status: 403 }
				)
			};
		}

		// Reads are allowed for a viewer in every authority state, including read-only suspension.
		if (capability === 'view') {
			return { auth, access, automation };
		}

		// Writes fail closed under either authority axis, before the per-capability permission check so the
		// caller sees the platform reason rather than a bare permission denial.
		if (automation.authority_state === 'security_suspended') {
			return {
				response: json(
					{ error: 'Automation is suspended for this organization.', reason: 'security_suspended' },
					{ status: 403 }
				)
			};
		}
		if (automation.authority_state === 'operationally_disabled') {
			return {
				response: json(
					{
						error: 'Automation is temporarily unavailable for this organization.',
						reason: 'operationally_disabled'
					},
					{ status: 403 }
				)
			};
		}

		const capable =
			capability === 'manage'
				? automation.can_manage
				: capability === 'activate'
					? automation.can_activate
					: automation.can_control_enrollment;
		if (!capable) {
			return {
				response: json(
					{ error: 'You do not have access to do that.', reason: 'permission_denied' },
					{ status: 403 }
				)
			};
		}

		return { auth, access, automation };
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError) {
			return {
				response: json(
					{ error: 'Authentication or organization membership required.' },
					{ status: 401 }
				)
			};
		}
		console.error('Could not resolve automation access.', error);
		return { response: json({ error: 'Access could not be verified.' }, { status: 500 }) };
	}
}
