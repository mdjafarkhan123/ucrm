import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Tables } from '$lib/database.types';
import { isKnownExperience } from '$lib/experience/definitions';

export type AccessClient = SupabaseClient<Database>;
export type LimitKey = 'employee_seats' | 'website_chat_widgets' | 'marketing_email_recipients';
export type LimitState = 'unlimited' | 'not_included' | 'numeric';
// The stored scope vocabulary. 'assigned' is the only narrowing any permission declares today; the type stays
// open so a later scope does not have to be threaded through every reader at once.
export type PermissionScope = 'all' | 'assigned' | (string & {});

export type OrganizationBilling = {
	paid_through_date: string | null;
	paid_through_source: string | null;
	grace_ends_at: string | null;
	is_overdue: boolean;
	is_in_grace: boolean;
};

export type FreeAccessGrant = {
	grant_id: string;
	starts_at: string;
	access_until_date: string | null;
};

export type FreeAccessState = {
	active: FreeAccessGrant | null;
	future: FreeAccessGrant | null;
};

export type EffectiveOrganizationAccess = {
	organization: Pick<Tables<'organizations'>, 'id' | 'name' | 'slug' | 'lifecycle_status'>;
	billing: OrganizationBilling;
	// The organization's agreement in effect and the edition it agreed to; null when it has none, which
	// leaves every capability off.
	package: {
		package_id: string;
		slug: string;
		edition_id: string;
		edition_number: number;
		edition_status: 'published' | 'superseded';
		name: string;
		promise: string | null;
		agreement_id: string;
		billing_interval: 'month' | 'year';
		agreed_price_usd_cents: number;
		currency: 'USD';
		effective_from: string;
	} | null;
	features: Record<string, boolean>;
	package_features: Record<string, boolean>;
	feature_overrides: Record<
		string,
		{
			state: 'on' | 'off';
			starts_at: string;
			expires_at: string | null;
			reason: string | null;
			is_legacy_import: boolean;
		}
	>;
	limits: Record<
		LimitKey,
		{
			state: LimitState;
			value: number | null;
			is_unlimited: boolean;
			source: 'package' | 'override';
		}
	>;
	limit_overrides: Partial<
		Record<
			LimitKey,
			{
				state: LimitState;
				value: number | null;
				is_unlimited: boolean;
				starts_at: string;
				expires_at: string | null;
			}
		>
	>;
	member: { user_id: string; role: string } | null;
	permissions: Record<string, boolean>;
	// How much of each held permission the member may reach. 'all' is the answer for every permission that
	// never opted into narrowing, so a caller that ignores this map behaves exactly as it did before scopes
	// existed. Only a key the member actually holds appears here.
	permission_scopes: Record<string, PermissionScope>;
	free_access: FreeAccessState;
};

export class OrganizationAccessNotFoundError extends Error {
	constructor(message = 'Organization was not found.') {
		super(message);
		this.name = 'OrganizationAccessNotFoundError';
	}
}

// Which package feature a permission belongs to. A list means the permission serves any one of those
// features, so it stays on while at least one of them is in the package.
const permissionFeaturePrefixes: Array<[string, string | string[]]> = [
	['customer.', 'core.customers_properties'],
	['customers.', 'core.customers_properties'],
	['property.', 'core.customers_properties'],
	['properties.', 'core.customers_properties'],
	['request.', 'core.requests_assessments'],
	['requests.', 'core.requests_assessments'],
	['pipeline.', 'sales.pipeline'],
	['quote.', 'core.quotes'],
	['quotes.', 'core.quotes'],
	// The price list only exists to be quoted from, so it rides on the same entitlement as quotes.
	['catalog.', 'core.quotes'],
	['job.', 'core.jobs'],
	['jobs.', 'core.jobs'],
	['schedule.', 'core.schedule'],
	['invoice.', 'core.invoices_payments'],
	['invoices.', 'core.invoices_payments'],
	['payment.', 'core.invoices_payments'],
	['payments.', 'core.invoices_payments'],
	['inbox.', 'communications.inbox'],
	['portal.', 'portal.client'],
	// Automation (Part 6) rides on the `automations` feature.
	['automations.', 'automations'],
	['marketing.', 'marketing'],
	// Google review requests and private feedback belong to the plan's Reputation tools.
	['reviews.', 'growth.reputation'],
	['report.', 'reporting.advanced'],
	['reports.', 'reporting.advanced'],
	['team.', 'core.team'],
	// Time, expenses and field records are kept against a job's visits, so they go with Jobs.
	['time.', 'core.jobs'],
	['expenses.', 'core.jobs'],
	['field_records.', 'core.jobs'],
	// A feature's own Settings pages go with it. Business details have no feature and always show.
	['settings.quotes.', 'core.quotes'],
	['settings.price_book.', 'core.quotes'],
	['settings.invoices.', 'core.invoices_payments'],
	['settings.payments.', 'core.invoices_payments'],
	['settings.taxes.', ['core.quotes', 'core.invoices_payments']],
	['settings.checklists.', 'core.jobs'],
	// Online forms create a request, an assessment, or a job.
	['settings.forms.', ['core.requests_assessments', 'core.jobs']]
];

function todayInTimeZone(timezone: string, now: Date) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: timezone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(now);
}

function computeCommercialBilling(
	row: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
	} | null,
	commercialTimezone: string | null,
	now: Date,
	hasActiveFreeAccess: boolean
): OrganizationBilling {
	const paidThroughDate = row?.paid_through_date ?? null;
	if (!paidThroughDate) {
		return {
			paid_through_date: null,
			paid_through_source: row?.paid_through_source ?? null,
			grace_ends_at: null,
			is_overdue: false,
			is_in_grace: false
		};
	}

	if (hasActiveFreeAccess) {
		return {
			paid_through_date: paidThroughDate,
			paid_through_source: row?.paid_through_source ?? null,
			grace_ends_at: row?.grace_ends_at ?? null,
			is_overdue: false,
			is_in_grace: false
		};
	}

	const isOverdue = todayInTimeZone(commercialTimezone ?? 'UTC', now) > paidThroughDate;
	const graceEndsAt = row?.grace_ends_at ?? null;

	return {
		paid_through_date: paidThroughDate,
		paid_through_source: row?.paid_through_source ?? null,
		grace_ends_at: graceEndsAt,
		is_overdue: isOverdue,
		is_in_grace:
			isOverdue && graceEndsAt !== null && now.getTime() <= new Date(graceEndsAt).getTime()
	};
}

function computeFreeAccessState(
	events: Array<{
		id: string;
		target_grant_id: string | null;
		action: string;
		starts_at: string;
		access_until_date: string | null;
		occurred_at: string;
	}>,
	todayDate: string
): FreeAccessState {
	const roots = new Map<string, typeof events>();
	for (const event of events) {
		const rootId = event.target_grant_id ?? event.id;
		const group = roots.get(rootId);
		if (group) group.push(event);
		else roots.set(rootId, [event]);
	}

	let active: FreeAccessGrant | null = null;
	let future: FreeAccessGrant | null = null;
	for (const [rootId, group] of roots) {
		const latest = [...group].sort(
			(a, b) => Date.parse(b.occurred_at) - Date.parse(a.occurred_at)
		)[0];
		if (latest.action === 'end') continue;
		const rootEvent = group.find((item) => item.target_grant_id === null);
		if (!rootEvent) continue;

		const grant: FreeAccessGrant = {
			grant_id: rootId,
			starts_at: rootEvent.starts_at,
			access_until_date: latest.access_until_date
		};
		if (
			rootEvent.starts_at <= todayDate &&
			(grant.access_until_date === null || grant.access_until_date >= todayDate)
		) {
			active = grant;
		} else if (rootEvent.starts_at > todayDate) {
			future = grant;
		}
	}

	return { active, future };
}

type LimitRow = { state: string; value: number | null; is_unlimited: boolean; source: string };

// Everything one member's access depends on, read in one call by `public.organization_access_snapshot`
// (SECURITY INVOKER, so the caller's RLS applies as it did to the separate reads it replaced).
type AccessSnapshot = {
	organization: { id: string; name: string; slug: string; lifecycle_status: string };
	agreement: {
		id: string;
		edition_id: string;
		billing_interval: 'month' | 'year';
		agreed_price_usd_cents: number;
		effective_from: string;
	} | null;
	edition: {
		id: string;
		package_id: string;
		edition_number: number;
		status: 'published' | 'superseded';
		name: string;
		promise: string | null;
	} | null;
	package: { id: string; slug: string } | null;
	capabilities: string[];
	edition_capabilities: string[];
	capability_exceptions: Array<{
		capability_key: string;
		state: 'on' | 'off';
		starts_at: string;
		ends_at: string;
		reason: string;
	}>;
	allowance_exceptions: Array<{
		allowance_key: string;
		state: LimitState;
		value: number | null;
		starts_at: string;
		ends_at: string;
	}>;
	commercial_state: {
		paid_through_date: string | null;
		paid_through_source: string | null;
		grace_ends_at: string | null;
	} | null;
	commercial_settings: { commercial_timezone: string | null } | null;
	free_access_events: Array<{
		id: string;
		target_grant_id: string | null;
		action: string;
		starts_at: string;
		access_until_date: string | null;
		occurred_at: string;
	}>;
	employee_seat_limit: LimitRow | null;
	website_chat_widgets_limit: LimitRow | null;
	marketing_email_limit: LimitRow | null;
	membership: { user_id: string; role: string } | null;
	role_permissions: Array<{ permission_key: string; access_scope: string | null }>;
	member_permission_overrides: Array<{
		permission_key: string;
		override_state: string;
		access_scope: string | null;
	}>;
	// Which Industry experience governs the Organization (`public.organization_experience_basis`) and the
	// family of every capability. Both are optional here so a snapshot without them fails closed.
	experience?: {
		state: 'confirmed' | 'planned' | 'none';
		experience?: string;
		definition_version?: number;
		families?: string[];
	};
	capability_families?: Record<string, string>;
};

function featureForPermission(permissionKey: string) {
	return (
		permissionFeaturePrefixes.find(([prefix]) => permissionKey.startsWith(prefix))?.[1] ?? null
	);
}

// The package features a permission rides on; none for a permission every plan has.
export function featureKeysForPermission(permissionKey: string): string[] {
	const featureKey = featureForPermission(permissionKey);
	if (!featureKey) return [];
	return Array.isArray(featureKey) ? featureKey : [featureKey];
}

// The TypeScript twin of private.member_permission_scope: an override wins over the role, a denied override
// is no permission at all rather than a scope, and anything unstated is 'all'. Both package paths below
// call this so the rule cannot drift between them -- or away from the SQL, which is the real boundary.
function resolveMemberPermissions(
	snapshot: AccessSnapshot,
	features: Record<string, boolean>
): {
	permissions: Record<string, boolean>;
	permission_scopes: Record<string, PermissionScope>;
} {
	const resolved = new Map<string, { enabled: boolean; scope: PermissionScope }>(
		snapshot.role_permissions.map((item) => [
			item.permission_key,
			{ enabled: true, scope: (item.access_scope ?? 'all') as PermissionScope }
		])
	);
	for (const override of snapshot.member_permission_overrides) {
		resolved.set(override.permission_key, {
			enabled: override.override_state === 'grant',
			scope: (override.access_scope ?? 'all') as PermissionScope
		});
	}

	const permissions: Record<string, boolean> = {};
	const permission_scopes: Record<string, PermissionScope> = {};
	for (const [permissionKey, { enabled, scope }] of resolved) {
		const granted = enabled && permissionIsEnabled(permissionKey, features);
		permissions[permissionKey] = granted;
		if (granted) permission_scopes[permissionKey] = scope;
	}
	return { permissions, permission_scopes };
}

export function permissionIsEnabled(permissionKey: string, features: Record<string, boolean>) {
	const featureKey = featureForPermission(permissionKey);
	if (!featureKey) return true;
	return Array.isArray(featureKey)
		? featureKey.some((key) => features[key] === true)
		: features[featureKey] === true;
}

/**
 * The Industry experience that governs an Organization, as far as the access answer is concerned
 * (multi-industry foundation B5/B6). `confirmed` is the reviewed profile; `planned` is the one experience the
 * agreed edition is sold to, used until Uplift has reviewed the business.
 */
export type ExperienceBasis = {
	kind: 'confirmed' | 'planned';
	experience: string;
	definition_version: number;
	/** The capability families the definition makes eligible. */
	families: string[];
};

export type CapabilityFamilies = ReadonlyMap<string, string>;

/**
 * The access an Organization has once its Industry experience takes part: a capability stays on only when the
 * Package gives it AND the experience's capability families allow it. A capability whose family is unknown
 * fails closed. Permissions are then narrowed by those capabilities exactly as they are for the Package.
 */
export function experienceAwareAccess(
	packageAccess: EffectiveOrganizationAccess,
	basis: ExperienceBasis | null,
	capabilityFamilies: CapabilityFamilies
): EffectiveOrganizationAccess {
	// No experience to judge against -- unknown, missing or broken profile -- allows nothing.
	const eligible = new Set(basis?.families ?? []);
	const features = Object.fromEntries(
		Object.entries(packageAccess.features).map(([key, on]) => {
			const family = capabilityFamilies.get(key);
			return [key, on && family !== undefined && eligible.has(family)];
		})
	);

	const permissions: Record<string, boolean> = {};
	const permission_scopes: Record<string, PermissionScope> = {};
	for (const [key, granted] of Object.entries(packageAccess.permissions)) {
		const kept = granted && permissionIsEnabled(key, features);
		permissions[key] = kept;
		if (kept && key in packageAccess.permission_scopes)
			permission_scopes[key] = packageAccess.permission_scopes[key];
	}
	return { ...packageAccess, features, permissions, permission_scopes };
}

// The snapshot's experience answer, trusted only for an experience and version this build of the app knows.
function experienceBasisFromSnapshot(snapshot: AccessSnapshot): ExperienceBasis | null {
	const answer = snapshot.experience;
	if (!answer || (answer.state !== 'confirmed' && answer.state !== 'planned')) return null;
	if (
		typeof answer.experience !== 'string' ||
		typeof answer.definition_version !== 'number' ||
		!Array.isArray(answer.families) ||
		!isKnownExperience(answer.experience, answer.definition_version)
	)
		return null;
	return {
		kind: answer.state,
		experience: answer.experience,
		definition_version: answer.definition_version,
		families: answer.families
	};
}

function effectiveLimit(row: LimitRow | null, label: string) {
	if (!row) throw new Error(`The ${label} could not be resolved.`);
	return {
		value: row.value,
		is_unlimited: row.is_unlimited,
		state: row.state as LimitState,
		source: row.source as 'package' | 'override'
	};
}

function resolvePackage(snapshot: AccessSnapshot): EffectiveOrganizationAccess['package'] {
	const { agreement, edition, package: packageRow } = snapshot;
	if (!agreement) return null;
	if (!edition || !packageRow) throw new Error('The organization package edition is missing.');
	return {
		package_id: packageRow.id,
		slug: packageRow.slug,
		edition_id: edition.id,
		edition_number: edition.edition_number,
		edition_status: edition.status,
		name: edition.name,
		promise: edition.promise,
		agreement_id: agreement.id,
		billing_interval: agreement.billing_interval,
		agreed_price_usd_cents: agreement.agreed_price_usd_cents,
		currency: 'USD',
		effective_from: agreement.effective_from
	};
}

async function loadAccessSnapshot(
	client: AccessClient,
	organizationId: string,
	userId: string | undefined,
	now: Date
) {
	const { data, error } = await client.rpc('organization_access_snapshot', {
		target_organization_id: organizationId,
		target_user_id: userId,
		at: now.toISOString()
	});
	if (error) throw error;
	const snapshot = data as unknown as AccessSnapshot | null;
	if (!snapshot) throw new OrganizationAccessNotFoundError();
	return snapshot;
}

/**
 * What the Organization's Package and the member's role give, before the Industry experience takes part.
 * Only the access comparison reads this; everything that decides what someone may do uses
 * `resolveOrganizationAccess`.
 */
export async function resolvePackageAccess(
	client: AccessClient,
	organizationId: string,
	userId?: string,
	now = new Date()
): Promise<EffectiveOrganizationAccess> {
	return packageAccessFromSnapshot(
		await loadAccessSnapshot(client, organizationId, userId, now),
		userId,
		now
	);
}

/**
 * The one answer to "what may this person do here": the Package and role answer narrowed by the Industry
 * experience (multi-industry foundation B6). Menu, pages, APIs and record scopes all read this.
 */
export async function resolveOrganizationAccess(
	client: AccessClient,
	organizationId: string,
	userId?: string,
	now = new Date()
): Promise<EffectiveOrganizationAccess> {
	const snapshot = await loadAccessSnapshot(client, organizationId, userId, now);
	return experienceAwareAccess(
		packageAccessFromSnapshot(snapshot, userId, now),
		experienceBasisFromSnapshot(snapshot),
		new Map(Object.entries(snapshot.capability_families ?? {}))
	);
}

function packageAccessFromSnapshot(
	snapshot: AccessSnapshot,
	userId: string | undefined,
	now: Date
): EffectiveOrganizationAccess {
	const limits = {
		employee_seats: effectiveLimit(snapshot.employee_seat_limit, 'employee seat limit'),
		website_chat_widgets: effectiveLimit(
			snapshot.website_chat_widgets_limit,
			'website chat widgets limit'
		),
		marketing_email_recipients: effectiveLimit(
			snapshot.marketing_email_limit,
			'Marketing email allowance'
		)
	};

	const commercialTimezone = snapshot.commercial_settings?.commercial_timezone ?? null;
	const freeAccessState = computeFreeAccessState(
		snapshot.free_access_events,
		todayInTimeZone(commercialTimezone ?? 'UTC', now)
	);

	// Exceptions arrive already filtered to those in effect, newest first, so the first one per key wins.
	const editionCapabilities = new Set(snapshot.edition_capabilities);
	const capabilityExceptions = new Map<string, AccessSnapshot['capability_exceptions'][number]>();
	for (const item of snapshot.capability_exceptions) {
		if (!capabilityExceptions.has(item.capability_key))
			capabilityExceptions.set(item.capability_key, item);
	}
	const allowanceExceptions = new Map<string, AccessSnapshot['allowance_exceptions'][number]>();
	for (const item of snapshot.allowance_exceptions) {
		if (!allowanceExceptions.has(item.allowance_key))
			allowanceExceptions.set(item.allowance_key, item);
	}
	const packageFeatureFlags = Object.fromEntries(
		snapshot.capabilities.map((key) => [key, editionCapabilities.has(key)])
	);
	const features = Object.fromEntries(
		snapshot.capabilities.map((key) => {
			const exception = capabilityExceptions.get(key);
			return [key, exception ? exception.state === 'on' : editionCapabilities.has(key)];
		})
	);

	let member: EffectiveOrganizationAccess['member'] = null;
	let permissions: Record<string, boolean> = {};
	let permissionScopes: Record<string, PermissionScope> = {};
	if (userId) {
		if (!snapshot.membership)
			throw new OrganizationAccessNotFoundError('Organization membership was not found.');
		member = snapshot.membership;
		const resolved = resolveMemberPermissions(snapshot, features);
		permissions = resolved.permissions;
		permissionScopes = resolved.permission_scopes;
	}

	const { organization } = snapshot;
	return {
		organization: {
			id: organization.id,
			name: organization.name,
			slug: organization.slug,
			lifecycle_status:
				organization.lifecycle_status as EffectiveOrganizationAccess['organization']['lifecycle_status']
		},
		billing: computeCommercialBilling(
			snapshot.commercial_state,
			commercialTimezone,
			now,
			freeAccessState.active !== null
		),
		package: resolvePackage(snapshot),
		features,
		package_features: packageFeatureFlags,
		feature_overrides: Object.fromEntries(
			[...capabilityExceptions].map(([key, item]) => [
				key,
				{
					state: item.state,
					starts_at: item.starts_at,
					expires_at: item.ends_at,
					reason: item.reason,
					is_legacy_import: false
				}
			])
		),
		limits,
		limit_overrides: Object.fromEntries(
			[...allowanceExceptions].map(([key, item]) => [
				key,
				{
					state: item.state,
					value: item.value,
					is_unlimited: item.state === 'unlimited',
					starts_at: item.starts_at,
					expires_at: item.ends_at
				}
			])
		),
		member,
		permissions,
		permission_scopes: permissionScopes,
		free_access: freeAccessState
	};
}
