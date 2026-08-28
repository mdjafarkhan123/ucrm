import { describe, expect, it } from 'vitest';
import {
	OrganizationAccessNotFoundError,
	permissionIsEnabled,
	resolveOrganizationAccess,
	type AccessClient
} from './effective';

type QueryResult = { data: unknown; error: null };

function query(result: QueryResult) {
	const builder = {
		select: () => builder,
		eq: () => builder,
		in: () => builder,
		order: () => builder,
		limit: () => builder,
		maybeSingle: () =>
			Promise.resolve({
				...result,
				data: Array.isArray(result.data) ? (result.data[0] ?? null) : result.data
			}),
		single: () => Promise.resolve(result),
		then: (resolve: (value: QueryResult) => unknown) => Promise.resolve(result).then(resolve)
	};
	return builder;
}

function clientFor(rows: Record<string, QueryResult>) {
	return {
		from: (table: string) => query(rows[table] ?? { data: [], error: null }),
		rpc: (fn: string) => {
			const result = rows[fn] ?? { data: [], error: null };
			const data = Array.isArray(result.data) ? result.data : result.data ? [result.data] : [];
			return Promise.resolve({ ...result, data });
		}
	} as unknown as AccessClient;
}

const baseRows = {
	organizations: {
		data: {
			id: 'org-a',
			name: 'Organization A',
			lifecycle_status: 'active',
			package_key: 'growth',
			scheduled_package_key: null,
			scheduled_package_effective_at: null
		},
		error: null
	},
	platform_packages: {
		data: [
			{ package_key: 'starter', display_name: 'Starter', sort_order: 1 },
			{ package_key: 'growth', display_name: 'Growth', sort_order: 2 },
			{ package_key: 'elite', display_name: 'Elite', sort_order: 3 }
		],
		error: null
	},
	features: {
		data: [
			{ feature_key: 'core.dashboard', description: 'Dashboard' },
			{ feature_key: 'core.customers_properties', description: 'Customers' },
			{ feature_key: 'core.team', description: 'Team' },
			{ feature_key: 'core.invoices_payments', description: 'Finance' },
			{ feature_key: 'sales.pipeline', description: 'Pipeline' },
			{ feature_key: 'growth.reputation', description: 'Reputation' }
		],
		error: null
	},
	package_features: {
		data: [
			{ package_key: 'growth', feature_key: 'core.dashboard' },
			{ package_key: 'growth', feature_key: 'core.customers_properties' },
			{ package_key: 'growth', feature_key: 'core.team' },
			{ package_key: 'growth', feature_key: 'core.invoices_payments' },
			{ package_key: 'growth', feature_key: 'sales.pipeline' },
			{ package_key: 'elite', feature_key: 'growth.reputation' }
		],
		error: null
	},
	effective_employee_seat_limit: {
		data: { state: 'numeric', value: 4, is_unlimited: false, source: 'override' },
		error: null
	},
	effective_website_chat_widgets_limit: {
		data: { state: 'not_included', value: null, is_unlimited: false, source: 'package' },
		error: null
	},
	organization_feature_overrides: {
		data: [
			{
				feature_key: 'core.team',
				override_state: 'off',
				starts_at: '2026-01-01T00:00:00.000Z',
				expires_at: null
			},
			{
				feature_key: 'core.dashboard',
				override_state: 'off',
				starts_at: '2025-01-01T00:00:00.000Z',
				expires_at: '2025-02-01T00:00:00.000Z'
			},
			{
				feature_key: 'growth.reputation',
				override_state: 'on',
				starts_at: '2027-01-01T00:00:00.000Z',
				expires_at: null
			}
		],
		error: null
	},
	organization_limit_overrides: {
		data: [
			{
				limit_key: 'employee_seats',
				limit_value: 4,
				is_unlimited: false,
				starts_at: '2026-01-01T00:00:00.000Z',
				expires_at: null
			}
		],
		error: null
	},
	organization_commercial_state: {
		data: {
			paid_through_date: '2026-12-31',
			paid_through_source: 'renewal',
			grace_ends_at: '2027-01-08T04:59:59.999Z'
		},
		error: null
	},
	organization_commercial_settings: {
		data: { commercial_timezone: 'America/New_York' },
		error: null
	},
	organization_package_assignments: { data: [], error: null },
	organization_members: { data: { user_id: 'user-a', role: 'sales' }, error: null },
	role_permissions: {
		data: [
			{ permission_key: 'customer.view' },
			{ permission_key: 'pipeline.view' },
			{ permission_key: 'team.manage' }
		],
		error: null
	},
	organization_member_permission_overrides: {
		data: [
			{ permission_key: 'pipeline.view', override_state: 'deny' },
			{ permission_key: 'team.manage', override_state: 'grant' },
			{ permission_key: 'invoice.view', override_state: 'grant' }
		],
		error: null
	}
};

describe('resolveOrganizationAccess', () => {
	it('combines package defaults, active overrides, limits, and member permissions', async () => {
		const access = await resolveOrganizationAccess(
			clientFor(baseRows),
			'org-a',
			'user-a',
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.package.effective_key).toBe('growth');
		expect(access.features['core.team']).toBe(false);
		expect(access.features['core.dashboard']).toBe(true);
		expect(access.features['growth.reputation']).toBe(false);
		expect(access.limits.employee_seats).toEqual({
			value: 4,
			is_unlimited: false,
			state: 'numeric',
			source: 'override'
		});
		expect(access.permissions).toMatchObject({
			'customer.view': true,
			'pipeline.view': false,
			'team.manage': false,
			'invoice.view': true
		});
	});

	it('applies a due package downgrade/upgrade schedule before resolving features', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		(rows.organizations.data as Record<string, unknown>).scheduled_package_key = 'elite';
		(rows.organizations.data as Record<string, unknown>).scheduled_package_effective_at =
			'2026-08-08T00:00:00.000Z';

		const access = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.package.current_key).toBe('growth');
		expect(access.package.effective_key).toBe('elite');
		expect(access.features['growth.reputation']).toBe(true);
	});

	it('uses the commercial calendar date and stored grace deadline across a DST boundary', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		rows.organization_commercial_state = {
			data: {
				paid_through_date: '2026-03-08',
				paid_through_source: 'renewal',
				grace_ends_at: '2026-03-16T03:59:59.999Z'
			},
			error: null
		};

		const beforeLocalMidnight = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-03-09T03:30:00.000Z')
		);
		const afterLocalMidnight = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-03-09T04:30:00.000Z')
		);

		expect(beforeLocalMidnight.billing).toMatchObject({
			paid_through_date: '2026-03-08',
			is_overdue: false,
			is_in_grace: false
		});
		expect(afterLocalMidnight.billing).toEqual({
			paid_through_date: '2026-03-08',
			paid_through_source: 'renewal',
			grace_ends_at: '2026-03-16T03:59:59.999Z',
			is_overdue: true,
			is_in_grace: true
		});
	});

	it('reports no free access grant and unmodified overdue billing when none exists', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		rows.organization_commercial_state = {
			data: {
				paid_through_date: '2026-01-01',
				paid_through_source: 'renewal',
				grace_ends_at: '2026-01-08T04:59:59.999Z'
			},
			error: null
		};

		const access = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.free_access).toEqual({ active: null, future: null });
		expect(access.billing.is_overdue).toBe(true);
	});

	it('an active free access grant overrides overdue billing regardless of the paid-through date', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		rows.organization_commercial_state = {
			data: {
				paid_through_date: '2026-01-01',
				paid_through_source: 'renewal',
				grace_ends_at: '2026-01-08T04:59:59.999Z'
			},
			error: null
		};
		rows.organization_free_access_events = {
			data: [
				{
					id: 'grant-1',
					target_grant_id: null,
					action: 'grant',
					starts_at: '2026-08-01',
					access_until_date: '2026-09-01',
					occurred_at: '2026-08-01T00:00:00.000Z'
				}
			],
			error: null
		};

		const access = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.free_access.active).toEqual({
			grant_id: 'grant-1',
			starts_at: '2026-08-01',
			access_until_date: '2026-09-01'
		});
		expect(access.free_access.future).toBeNull();
		expect(access.billing.is_overdue).toBe(false);
		expect(access.billing.is_in_grace).toBe(false);
	});

	it('folds a grant, an extension, and a scheduled future grant to their current active and future state', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		rows.organization_free_access_events = {
			data: [
				{
					id: 'grant-1',
					target_grant_id: null,
					action: 'grant',
					starts_at: '2026-08-01',
					access_until_date: '2026-08-15',
					occurred_at: '2026-08-01T00:00:00.000Z'
				},
				{
					id: 'extend-1',
					target_grant_id: 'grant-1',
					action: 'extend',
					starts_at: '2026-08-01',
					access_until_date: '2026-09-01',
					occurred_at: '2026-08-05T00:00:00.000Z'
				},
				{
					id: 'grant-2',
					target_grant_id: null,
					action: 'grant',
					starts_at: '2026-10-01',
					access_until_date: null,
					occurred_at: '2026-08-06T00:00:00.000Z'
				}
			],
			error: null
		};

		const access = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.free_access.active).toEqual({
			grant_id: 'grant-1',
			starts_at: '2026-08-01',
			access_until_date: '2026-09-01'
		});
		expect(access.free_access.future).toEqual({
			grant_id: 'grant-2',
			starts_at: '2026-10-01',
			access_until_date: null
		});
	});

	it('excludes an ended grant from the active and future free access state', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		rows.organization_free_access_events = {
			data: [
				{
					id: 'grant-1',
					target_grant_id: null,
					action: 'grant',
					starts_at: '2026-08-01',
					access_until_date: null,
					occurred_at: '2026-08-01T00:00:00.000Z'
				},
				{
					id: 'end-1',
					target_grant_id: 'grant-1',
					action: 'end',
					starts_at: '2026-08-01',
					access_until_date: null,
					occurred_at: '2026-08-05T00:00:00.000Z'
				}
			],
			error: null
		};

		const access = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.free_access).toEqual({ active: null, future: null });
	});

	it('throws a typed not-found error when the organization is absent', async () => {
		const rows = {
			...structuredClone(baseRows),
			organizations: { data: null, error: null }
		};

		await expect(resolveOrganizationAccess(clientFor(rows), 'missing')).rejects.toBeInstanceOf(
			OrganizationAccessNotFoundError
		);
	});

	it('resolves a versioned assignment before legacy package columns', async () => {
		const rows = structuredClone(baseRows) as Record<string, QueryResult>;
		(rows.organizations.data as Record<string, unknown>).package_key = 'starter';
		(rows.organizations.data as Record<string, unknown>).scheduled_package_key = 'elite';
		(rows.organizations.data as Record<string, unknown>).scheduled_package_effective_at =
			'2026-08-08T00:00:00.000Z';
		rows.organization_package_assignments = {
			data: [{ package_version_id: 'version-growth-1', effective_at: '2026-08-01T00:00:00.000Z' }],
			error: null
		};
		rows.platform_package_versions = {
			data: [
				{
					id: 'version-growth-1',
					package_id: 'package-growth',
					display_name: 'Growth v1',
					status: 'published'
				}
			],
			error: null
		};
		rows.platform_packages = {
			data: [
				{ package_id: 'package-growth', package_key: 'growth' },
				{ package_id: 'package-starter', package_key: 'starter' },
				{ package_id: 'package-elite', package_key: 'elite' }
			],
			error: null
		};
		rows.platform_package_version_features = {
			data: [{ package_version_id: 'version-growth-1', feature_key: 'sales.pipeline' }],
			error: null
		};
		rows.organization_limit_overrides = { data: [], error: null };
		rows.effective_employee_seat_limit = {
			data: { state: 'numeric', value: 10, is_unlimited: false, source: 'package' },
			error: null
		};

		const access = await resolveOrganizationAccess(
			clientFor(rows),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.package.current_key).toBe('growth');
		expect(access.package.display_name).toBe('Growth v1');
		expect(access.package.scheduled_key).toBeNull();
		expect(access.features['sales.pipeline']).toBe(true);
		expect(access.limits.employee_seats).toEqual({
			value: 10,
			is_unlimited: false,
			state: 'numeric',
			source: 'package'
		});
	});
});

describe('permission entitlements', () => {
	it('turns the price list off with the quotes feature', () => {
		expect(permissionIsEnabled('catalog.edit', { 'core.quotes': true })).toBe(true);
		expect(permissionIsEnabled('catalog.edit', { 'core.quotes': false })).toBe(false);
		expect(permissionIsEnabled('catalog.view', {})).toBe(false);
	});

	it('leaves a permission with no feature of its own always on', () => {
		expect(permissionIsEnabled('organization.view', {})).toBe(true);
	});
});
