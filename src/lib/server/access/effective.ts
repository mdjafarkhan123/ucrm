import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Tables } from '$lib/database.types';

export type AccessClient = SupabaseClient<Database>;
export type PackageKey = 'starter' | 'growth' | 'elite';
export type LimitKey = 'employee_seats' | 'website_chat_widgets' | 'marketing_email_recipients';
export type LimitState = 'unlimited' | 'not_included' | 'numeric';
// The stored scope vocabulary. 'assigned' is the only narrowing any permission declares today; the type stays
// open so a later scope does not have to be threaded through every reader at once.
export type PermissionScope = 'all' | 'assigned' | (string & {});

export const PACKAGE_ORDER: Record<PackageKey, number> = {
	starter: 1,
	growth: 2,
	elite: 3
};

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
	package: {
		current_key: PackageKey;
		effective_key: PackageKey;
		package_id: string;
		version_id: string | null;
		version_number: number | null;
		status: 'draft' | 'published' | 'retired';
		display_name: string;
		public_description: string | null;
		price_usd_cents: number | null;
		currency: string;
		billing_period: string;
		scheduled_key: PackageKey | null;
		scheduled_effective_at: string | null;
	};
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

const permissionFeaturePrefixes: Array<[string, string]> = [
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
	// Automation (Part 6) rides on the `automations` feature. The legacy `automation.` prefix below
	// stays mapped to the retired `automation.workflows` key for immutable package history only.
	['automations.', 'automations'],
	['automation.', 'automation.workflows'],
	['marketing.', 'marketing'],
	// Google review requests and private feedback belong to the plan's Reputation tools.
	['reviews.', 'growth.reputation'],
	['report.', 'reporting.advanced'],
	['reports.', 'reporting.advanced'],
	['team.', 'core.team']
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

function packageKey(value: string): PackageKey {
	if (value === 'starter' || value === 'growth' || value === 'elite') return value;
	throw new Error(`Unsupported package key: ${value}`);
}

function isActiveWindow(row: { starts_at: string; expires_at: string | null }, now: number) {
	const startsAt = Date.parse(row.starts_at);
	const expiresAt = row.expires_at ? Date.parse(row.expires_at) : null;
	return startsAt <= now && (expiresAt === null || expiresAt > now);
}

function buildFeatureOverridesMap(
	featureOverrides: Array<{
		feature_key: string;
		override_state: string;
		starts_at: string;
		expires_at: string | null;
		reason?: string | null;
		is_legacy_import?: boolean;
	}>
): EffectiveOrganizationAccess['feature_overrides'] {
	return Object.fromEntries(
		featureOverrides.map((item) => [
			item.feature_key,
			{
				state: item.override_state as 'on' | 'off',
				starts_at: item.starts_at,
				expires_at: item.expires_at,
				reason: item.reason ?? null,
				is_legacy_import: item.is_legacy_import ?? true
			}
		])
	);
}

function buildLimitOverridesMap(
	limitOverrides: Array<{
		limit_key: string;
		limit_state?: string;
		limit_value: number | null;
		is_unlimited: boolean;
		starts_at: string;
		expires_at: string | null;
		reason?: string | null;
		is_legacy_import?: boolean;
	}>
): EffectiveOrganizationAccess['limit_overrides'] {
	return Object.fromEntries(
		limitOverrides.map((item) => [
			item.limit_key,
			{
				value: item.limit_value,
				is_unlimited: item.is_unlimited,
				state:
					(item.limit_state as LimitState | undefined) ??
					(item.is_unlimited
						? 'unlimited'
						: item.limit_value === null
							? 'not_included'
							: 'numeric'),
				starts_at: item.starts_at,
				expires_at: item.expires_at,
				reason: item.reason ?? null,
				is_legacy_import: item.is_legacy_import ?? true
			}
		])
	) as EffectiveOrganizationAccess['limit_overrides'];
}

type LimitRow = { state: string; value: number | null; is_unlimited: boolean; source: string };
type FeatureOverrideRow = {
	feature_key: string;
	override_state: string;
	starts_at: string;
	expires_at: string | null;
	reason: string | null;
	is_legacy_import: boolean;
};
type LimitOverrideRow = {
	limit_key: string;
	limit_state: string;
	limit_value: number | null;
	is_unlimited: boolean;
	starts_at: string;
	expires_at: string | null;
};
type OrganizationRow = {
	id: string;
	name: string;
	slug: string;
	lifecycle_status: string;
	package_key: string;
	scheduled_package_key: string | null;
	scheduled_package_effective_at: string | null;
};

// Everything one member's access depends on, read in one call by `public.organization_access_snapshot`
// (SECURITY INVOKER, so the caller's RLS applies as it did to the separate reads it replaced).
type AccessSnapshot = {
	organization: OrganizationRow;
	assignment: { package_version_id: string; effective_at: string } | null;
	package_version: {
		id: string;
		package_id: string;
		version_number: number;
		display_name: string;
		public_description: string | null;
		price_usd_cents: number | null;
		currency: string;
		billing_period: string;
		status: string;
	} | null;
	platform_packages: Array<{
		package_id: string;
		package_key: string;
		display_name: string;
		sort_order: number;
		status: string;
		public_description: string | null;
		price_usd_cents: number | null;
		currency: string;
		billing_period: string;
	}>;
	features: Array<{ feature_key: string; description: string | null }>;
	package_features: Array<{ package_key: string; feature_key: string }>;
	package_version_features: Array<{ package_version_id: string; feature_key: string }>;
	feature_overrides: FeatureOverrideRow[];
	limit_overrides: LimitOverrideRow[];
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
};

function featureForPermission(permissionKey: string) {
	return (
		permissionFeaturePrefixes.find(([prefix]) => permissionKey.startsWith(prefix))?.[1] ?? null
	);
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
	return featureKey ? features[featureKey] === true : true;
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

// The package half differs between a versioned assignment and the legacy package columns; everything else
// about an organization's access is resolved the same way from the same rows.
function resolvePackage(snapshot: AccessSnapshot, now: Date) {
	const { organization, assignment } = snapshot;

	if (assignment) {
		const version = snapshot.package_version;
		if (!version) throw new Error('The organization package version is missing.');
		const packageDefinition = snapshot.platform_packages.find(
			(item) => item.package_id === version.package_id
		);
		if (!packageDefinition) throw new Error('The organization package definition is missing.');
		const currentPackageKey = packageKey(packageDefinition.package_key);
		return {
			package: {
				current_key: currentPackageKey,
				effective_key: currentPackageKey,
				package_id: packageDefinition.package_id,
				version_id: version.id,
				version_number: version.version_number,
				status: version.status as 'draft' | 'published' | 'retired',
				display_name: version.display_name,
				public_description: version.public_description,
				price_usd_cents: version.price_usd_cents,
				currency: version.currency,
				billing_period: version.billing_period,
				scheduled_key: null,
				scheduled_effective_at: null
			},
			packageFeatureKeys: new Set(snapshot.package_version_features.map((item) => item.feature_key))
		};
	}

	const currentPackageKey = packageKey(organization.package_key);
	const scheduledPackageKey = organization.scheduled_package_key
		? packageKey(organization.scheduled_package_key)
		: null;
	const scheduledAt = organization.scheduled_package_effective_at;
	const scheduledIsDue =
		scheduledPackageKey !== null &&
		scheduledAt !== null &&
		Date.parse(scheduledAt) <= now.getTime();
	const effectivePackageKey = scheduledIsDue ? scheduledPackageKey : currentPackageKey;
	const effectivePackage = snapshot.platform_packages.find(
		(item) => item.package_key === effectivePackageKey
	);
	if (!effectivePackage) throw new Error(`Package definition is missing: ${effectivePackageKey}`);
	return {
		package: {
			current_key: currentPackageKey,
			effective_key: effectivePackageKey,
			package_id: effectivePackage.package_id,
			version_id: null,
			version_number: null,
			status: effectivePackage.status as 'draft' | 'published' | 'retired',
			display_name: effectivePackage.display_name,
			public_description: effectivePackage.public_description,
			price_usd_cents: effectivePackage.price_usd_cents,
			currency: effectivePackage.currency,
			billing_period: effectivePackage.billing_period,
			scheduled_key: scheduledPackageKey,
			scheduled_effective_at: scheduledAt
		},
		packageFeatureKeys: new Set(
			snapshot.package_features
				.filter((item) => item.package_key === effectivePackageKey)
				.map((item) => item.feature_key)
		)
	};
}

export async function resolveOrganizationAccess(
	client: AccessClient,
	organizationId: string,
	userId?: string,
	now = new Date()
): Promise<EffectiveOrganizationAccess> {
	const { data, error } = await client.rpc('organization_access_snapshot', {
		target_organization_id: organizationId,
		target_user_id: userId,
		at: now.toISOString()
	});
	if (error) throw error;
	const snapshot = data as unknown as AccessSnapshot | null;
	if (!snapshot) throw new OrganizationAccessNotFoundError();

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

	const { package: resolvedPackage, packageFeatureKeys } = resolvePackage(snapshot, now);
	const nowMs = now.getTime();
	const featureOverrides = snapshot.feature_overrides.filter((item) => isActiveWindow(item, nowMs));
	const featureOverrideByKey = new Map(featureOverrides.map((item) => [item.feature_key, item]));
	const packageFeatureFlags = Object.fromEntries(
		snapshot.features.map((feature) => [
			feature.feature_key,
			packageFeatureKeys.has(feature.feature_key)
		])
	);
	const features = Object.fromEntries(
		snapshot.features.map((feature) => {
			const override = featureOverrideByKey.get(feature.feature_key);
			return [
				feature.feature_key,
				override ? override.override_state === 'on' : packageFeatureKeys.has(feature.feature_key)
			];
		})
	);
	const limitOverrides = snapshot.limit_overrides.filter((item) => isActiveWindow(item, nowMs));

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
		package: resolvedPackage,
		features,
		package_features: packageFeatureFlags,
		feature_overrides: buildFeatureOverridesMap(featureOverrides),
		limits,
		limit_overrides: buildLimitOverridesMap(limitOverrides),
		member,
		permissions,
		permission_scopes: permissionScopes,
		free_access: freeAccessState
	};
}
