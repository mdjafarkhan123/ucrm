import { describe, expect, it } from 'vitest';
import {
	OrganizationAccessNotFoundError,
	permissionIsEnabled,
	resolveOrganizationAccess,
	resolvePackageAccess,
	type AccessClient
} from './effective';

type Snapshot = Record<string, unknown>;

function clientFor(snapshot: Snapshot | null) {
	return {
		rpc: (fn: string) =>
			Promise.resolve(
				fn === 'organization_access_snapshot'
					? { data: snapshot, error: null }
					: { data: null, error: new Error(`Unexpected call to ${fn}`) }
			)
	} as unknown as AccessClient;
}

// The shape `public.organization_access_snapshot` returns: the agreement in effect, its edition and
// capabilities, and only the exceptions active at the requested moment, newest first.
const baseSnapshot: Snapshot = {
	organization: {
		id: 'org-a',
		name: 'Organization A',
		slug: 'organization-a',
		lifecycle_status: 'active'
	},
	agreement: {
		id: 'agreement-1',
		edition_id: 'edition-growth-1',
		billing_interval: 'month',
		agreed_price_usd_cents: 14900,
		effective_from: '2026-08-01T00:00:00.000Z'
	},
	edition: {
		id: 'edition-growth-1',
		package_id: 'package-growth',
		edition_number: 1,
		status: 'published',
		name: 'Growth',
		promise: 'Everything a growing crew needs.'
	},
	package: { id: 'package-growth', slug: 'growth' },
	capabilities: [
		'core.dashboard',
		'core.customers_properties',
		'core.team',
		'core.invoices_payments',
		'sales.pipeline',
		'growth.reputation'
	],
	capability_families: {
		'core.dashboard': 'shared_platform',
		'core.customers_properties': 'shared_platform',
		'core.team': 'shared_platform',
		'core.invoices_payments': 'field_service',
		'sales.pipeline': 'field_service',
		'growth.reputation': 'shared_platform'
	},
	experience: {
		state: 'confirmed',
		experience: 'contractor',
		definition_version: 1,
		families: ['shared_platform', 'field_service']
	},
	edition_capabilities: [
		'core.dashboard',
		'core.customers_properties',
		'core.team',
		'core.invoices_payments',
		'sales.pipeline'
	],
	capability_exceptions: [
		{
			capability_key: 'core.team',
			state: 'off',
			starts_at: '2026-08-01T00:00:00.000Z',
			ends_at: '2026-12-01T00:00:00.000Z',
			reason: 'Paused while the owner restructures the team.'
		}
	],
	allowance_exceptions: [
		{
			allowance_key: 'employee_seats',
			state: 'numeric',
			value: 4,
			starts_at: '2026-08-01T00:00:00.000Z',
			ends_at: '2026-12-01T00:00:00.000Z'
		}
	],
	commercial_state: {
		paid_through_date: '2026-12-31',
		paid_through_source: 'renewal',
		grace_ends_at: '2027-01-08T04:59:59.999Z'
	},
	commercial_settings: { commercial_timezone: 'America/New_York' },
	free_access_events: [],
	employee_seat_limit: { state: 'numeric', value: 4, is_unlimited: false, source: 'override' },
	website_chat_widgets_limit: {
		state: 'not_included',
		value: null,
		is_unlimited: false,
		source: 'package'
	},
	marketing_email_limit: {
		state: 'not_included',
		value: null,
		is_unlimited: false,
		source: 'package'
	},
	membership: { user_id: 'user-a', role: 'sales' },
	role_permissions: [
		{ permission_key: 'customer.view', access_scope: null },
		{ permission_key: 'pipeline.view', access_scope: null },
		{ permission_key: 'team.manage', access_scope: null }
	],
	member_permission_overrides: [
		{ permission_key: 'team.manage', override_state: 'grant', access_scope: null },
		{ permission_key: 'invoice.view', override_state: 'grant', access_scope: null }
	]
};

function snapshotWith(changes: Snapshot): Snapshot {
	return { ...structuredClone(baseSnapshot), ...changes };
}

describe('resolveOrganizationAccess', () => {
	it('combines the edition, active exceptions, limits, and member permissions', async () => {
		const access = await resolveOrganizationAccess(
			clientFor(baseSnapshot),
			'org-a',
			'user-a',
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.package).toEqual({
			package_id: 'package-growth',
			slug: 'growth',
			edition_id: 'edition-growth-1',
			edition_number: 1,
			edition_status: 'published',
			name: 'Growth',
			promise: 'Everything a growing crew needs.',
			agreement_id: 'agreement-1',
			billing_interval: 'month',
			agreed_price_usd_cents: 14900,
			currency: 'USD',
			effective_from: '2026-08-01T00:00:00.000Z'
		});
		expect(access.features['core.team']).toBe(false);
		expect(access.package_features['core.team']).toBe(true);
		expect(access.features['core.dashboard']).toBe(true);
		expect(access.features['growth.reputation']).toBe(false);
		expect(access.feature_overrides['core.team']).toMatchObject({
			state: 'off',
			expires_at: '2026-12-01T00:00:00.000Z'
		});
		expect(access.limits.employee_seats).toEqual({
			value: 4,
			is_unlimited: false,
			state: 'numeric',
			source: 'override'
		});
		expect(access.limit_overrides.employee_seats).toMatchObject({ state: 'numeric', value: 4 });
		expect(access.permissions).toMatchObject({
			'customer.view': true,
			'pipeline.view': true,
			'team.manage': false,
			'invoice.view': true
		});
	});

	it('turns off every screen of a capability the edition does not include', async () => {
		const snapshot = snapshotWith({
			edition_capabilities: (baseSnapshot.edition_capabilities as string[]).filter(
				(key) => key !== 'sales.pipeline'
			),
			capability_exceptions: []
		});

		const access = await resolveOrganizationAccess(
			clientFor(snapshot),
			'org-a',
			'user-a',
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.features['sales.pipeline']).toBe(false);
		expect(access.permissions['pipeline.view']).toBe(false);
		expect(access.permission_scopes['pipeline.view']).toBeUndefined();
		expect(access.permissions['customer.view']).toBe(true);
	});

	it('leaves every capability off and no package when the organization has no agreement', async () => {
		const snapshot = snapshotWith({
			agreement: null,
			edition: null,
			package: null,
			edition_capabilities: [],
			capability_exceptions: []
		});

		const access = await resolveOrganizationAccess(
			clientFor(snapshot),
			'org-a',
			'user-a',
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.package).toBeNull();
		expect(Object.values(access.features).every((enabled) => enabled === false)).toBe(true);
		expect(access.permissions['customer.view']).toBe(false);
	});

	it('refuses an agreement whose edition is missing instead of guessing', async () => {
		const snapshot = snapshotWith({ edition: null });

		await expect(resolveOrganizationAccess(clientFor(snapshot), 'org-a')).rejects.toThrow(
			'The organization package edition is missing.'
		);
	});

	it('uses the commercial calendar date and stored grace deadline across a DST boundary', async () => {
		const snapshot = snapshotWith({
			commercial_state: {
				paid_through_date: '2026-03-08',
				paid_through_source: 'renewal',
				grace_ends_at: '2026-03-16T03:59:59.999Z'
			}
		});

		const beforeLocalMidnight = await resolveOrganizationAccess(
			clientFor(snapshot),
			'org-a',
			undefined,
			new Date('2026-03-09T03:30:00.000Z')
		);
		const afterLocalMidnight = await resolveOrganizationAccess(
			clientFor(snapshot),
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
		const snapshot = snapshotWith({
			commercial_state: {
				paid_through_date: '2026-01-01',
				paid_through_source: 'renewal',
				grace_ends_at: '2026-01-08T04:59:59.999Z'
			}
		});

		const access = await resolveOrganizationAccess(
			clientFor(snapshot),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.free_access).toEqual({ active: null, future: null });
		expect(access.billing.is_overdue).toBe(true);
	});

	it('an active free access grant overrides overdue billing regardless of the paid-through date', async () => {
		const snapshot = snapshotWith({
			commercial_state: {
				paid_through_date: '2026-01-01',
				paid_through_source: 'renewal',
				grace_ends_at: '2026-01-08T04:59:59.999Z'
			},
			free_access_events: [
				{
					id: 'grant-1',
					target_grant_id: null,
					action: 'grant',
					starts_at: '2026-08-01',
					access_until_date: '2026-09-01',
					occurred_at: '2026-08-01T00:00:00.000Z'
				}
			]
		});

		const access = await resolveOrganizationAccess(
			clientFor(snapshot),
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
		const snapshot = snapshotWith({
			free_access_events: [
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
			]
		});

		const access = await resolveOrganizationAccess(
			clientFor(snapshot),
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
		const snapshot = snapshotWith({
			free_access_events: [
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
			]
		});

		const access = await resolveOrganizationAccess(
			clientFor(snapshot),
			'org-a',
			undefined,
			new Date('2026-08-09T00:00:00.000Z')
		);

		expect(access.free_access).toEqual({ active: null, future: null });
	});

	describe('Industry experience', () => {
		const resolve = (changes: Snapshot) =>
			resolveOrganizationAccess(clientFor(snapshotWith(changes)), 'org-a', 'user-a');

		it('keeps every Contractor capability on for the Contractor experience', async () => {
			const access = await resolve({});
			expect(access.features['sales.pipeline']).toBe(true);
			expect(access.features['core.invoices_payments']).toBe(true);
			expect(access.permissions['pipeline.view']).toBe(true);
		});

		it('turns off a capability whose family the experience does not allow, and the permissions riding on it', async () => {
			const access = await resolve({
				experience: {
					state: 'confirmed',
					experience: 'contractor',
					definition_version: 1,
					families: ['shared_platform']
				}
			});
			expect(access.features['core.customers_properties']).toBe(true);
			expect(access.features['sales.pipeline']).toBe(false);
			expect(access.permissions['pipeline.view']).toBe(false);
			expect(access.permission_scopes['pipeline.view']).toBeUndefined();
			expect(access.permissions['customer.view']).toBe(true);
		});

		it('does not let a temporary exception turn on a capability the experience does not allow', async () => {
			const access = await resolve({
				experience: {
					state: 'confirmed',
					experience: 'contractor',
					definition_version: 1,
					families: ['shared_platform']
				},
				capability_exceptions: [
					{
						capability_key: 'sales.pipeline',
						state: 'on',
						starts_at: '2026-08-01T00:00:00.000Z',
						ends_at: '2026-12-01T00:00:00.000Z',
						reason: 'Trial.'
					}
				]
			});
			expect(access.features['sales.pipeline']).toBe(false);
		});

		it('fails closed on a capability that has no family', async () => {
			const access = await resolve({
				capability_families: { 'core.customers_properties': 'shared_platform' }
			});
			expect(access.features['core.customers_properties']).toBe(true);
			expect(access.features['sales.pipeline']).toBe(false);
			expect(access.features['core.team']).toBe(false);
		});

		it.each([
			['no experience could be decided', { state: 'none', reason: 'no_single_experience' }],
			[
				'the experience is one this build does not know',
				{
					state: 'confirmed',
					experience: 'medspa',
					definition_version: 1,
					families: ['shared_platform', 'appointment_business', 'clinical_extension']
				}
			],
			[
				'the definition version is one this build does not know',
				{
					state: 'confirmed',
					experience: 'contractor',
					definition_version: 99,
					families: ['shared_platform', 'field_service']
				}
			],
			['the answer is missing', undefined]
		])('allows nothing when %s', async (_name, experience) => {
			const access = await resolve({ experience });
			expect(Object.values(access.features).some(Boolean)).toBe(false);
			expect(Object.values(access.permissions).some(Boolean)).toBe(false);
			expect(access.member).toEqual({ user_id: 'user-a', role: 'sales' });
		});

		it('leaves the package-only answer available for the access comparison', async () => {
			const access = await resolvePackageAccess(
				clientFor(snapshotWith({ experience: { state: 'none' } })),
				'org-a',
				'user-a'
			);
			expect(access.features['sales.pipeline']).toBe(true);
		});
	});

	it('throws a typed not-found error when the organization is absent', async () => {
		await expect(resolveOrganizationAccess(clientFor(null), 'missing')).rejects.toBeInstanceOf(
			OrganizationAccessNotFoundError
		);
	});
});

describe('permission entitlements', () => {
	it('turns the price list off with the quotes feature', () => {
		expect(permissionIsEnabled('catalog.edit', { 'core.quotes': true })).toBe(true);
		expect(permissionIsEnabled('catalog.edit', { 'core.quotes': false })).toBe(false);
		expect(permissionIsEnabled('catalog.view', {})).toBe(false);
	});

	it("ties a feature's Settings pages and job records to that feature", () => {
		const withoutQuotes = { 'core.jobs': true, 'core.invoices_payments': true };
		expect(permissionIsEnabled('settings.quotes.manage', withoutQuotes)).toBe(false);
		expect(permissionIsEnabled('settings.price_book.manage', withoutQuotes)).toBe(false);
		expect(permissionIsEnabled('settings.invoices.manage', withoutQuotes)).toBe(true);
		expect(permissionIsEnabled('settings.payments.manage', {})).toBe(false);
		expect(permissionIsEnabled('settings.checklists.manage', { 'core.jobs': false })).toBe(false);
		for (const key of ['time.track_own', 'expenses.record', 'field_records.record']) {
			expect(permissionIsEnabled(key, { 'core.jobs': true })).toBe(true);
			expect(permissionIsEnabled(key, { 'core.jobs': false })).toBe(false);
		}
		expect(permissionIsEnabled('settings.business.edit', {})).toBe(true);
	});

	it('keeps a permission shared by two features on while either is in the package', () => {
		expect(permissionIsEnabled('settings.taxes.manage', { 'core.quotes': true })).toBe(true);
		expect(permissionIsEnabled('settings.taxes.manage', { 'core.invoices_payments': true })).toBe(
			true
		);
		expect(permissionIsEnabled('settings.taxes.manage', {})).toBe(false);
		expect(permissionIsEnabled('settings.forms.manage', { 'core.jobs': true })).toBe(true);
		expect(
			permissionIsEnabled('settings.forms.manage', { 'core.requests_assessments': true })
		).toBe(true);
		expect(permissionIsEnabled('settings.forms.manage', { 'core.quotes': true })).toBe(false);
	});

	it('leaves a permission with no feature of its own always on', () => {
		expect(permissionIsEnabled('organization.view', {})).toBe(true);
	});
});
