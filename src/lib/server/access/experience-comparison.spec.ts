import { describe, expect, it } from 'vitest';
import { permissionIsEnabled, type EffectiveOrganizationAccess } from './effective';
import {
	compareAccess,
	experienceAwareAccess,
	hasDifferences,
	type ExperienceBasis
} from './experience-comparison';

const families = new Map([
	['core.quotes', 'field_service'],
	['core.jobs', 'field_service'],
	['core.schedule', 'field_service'],
	['core.customers_properties', 'field_service'],
	['core.requests_assessments', 'field_service'],
	['core.invoices_payments', 'field_service'],
	['communications.inbox', 'shared_platform'],
	['appointments', 'appointment_business']
]);

const contractor: ExperienceBasis = {
	kind: 'confirmed',
	experience: 'contractor',
	definition_version: 1,
	families: ['shared_platform', 'field_service']
};

// Built the way the resolver builds it: a permission is granted only while its package feature is on.
function access(features: string[], permissions: string[]) {
	const flags = Object.fromEntries(
		[...families.keys()].map((key) => [key, features.includes(key)])
	);
	return {
		features: flags,
		permissions: Object.fromEntries(
			permissions.map((key) => [key, permissionIsEnabled(key, flags)])
		),
		permission_scopes: { 'jobs.view': 'assigned' }
	} as unknown as EffectiveOrganizationAccess;
}

const permissions = [
	'quotes.view',
	'jobs.view',
	'customers.view',
	'files.view',
	'conversations.view_team'
];

describe('experience-aware access', () => {
	it('answers exactly as today for a Contractor on a full package', () => {
		const legacy = access(
			[
				'core.quotes',
				'core.jobs',
				'core.schedule',
				'core.customers_properties',
				'communications.inbox'
			],
			permissions
		);
		const aware = experienceAwareAccess(legacy, contractor, families);
		expect(aware.features).toEqual(legacy.features);
		expect(aware.permissions).toEqual(legacy.permissions);
		expect(aware.permission_scopes).toEqual({ 'jobs.view': 'assigned' });
		expect(hasDifferences(compareAccess(legacy, aware, contractor, families))).toBe(false);
	});

	it('shows a capability the experience does not allow as lost, with the cause, and its permissions with it', () => {
		const legacy = access(['core.quotes', 'core.jobs', 'appointments'], permissions);
		const wrongFamily: ExperienceBasis = { ...contractor, families: ['shared_platform'] };
		const aware = experienceAwareAccess(legacy, wrongFamily, families);
		const differences = compareAccess(legacy, aware, wrongFamily, families);
		expect(differences.features.map((c) => c.key)).toEqual([
			'appointments',
			'core.jobs',
			'core.quotes'
		]);
		expect(differences.features[0]).toMatchObject({
			direction: 'lost',
			cause: 'The contractor experience does not allow the appointment_business family.'
		});
		expect(differences.permissions.map((c) => c.key)).toEqual(['jobs.view', 'quotes.view']);
		expect(differences.permissions[0].cause).toContain('core.jobs');
		expect(aware.permission_scopes).toEqual({});
		expect(differences.navigation.map((c) => c.key)).toEqual(['jobs', 'quotes']);
	});

	it('fails closed for a capability with no family', () => {
		const legacy = access(['core.quotes'], ['quotes.view']);
		const aware = experienceAwareAccess(legacy, contractor, new Map());
		expect(aware.features['core.quotes']).toBe(false);
		const differences = compareAccess(legacy, aware, contractor, new Map());
		expect(differences.features[0].cause).toMatch(/no family/);
	});

	it('flags a gain as something that should not happen, and an unexplained permission loss', () => {
		const legacy = access([], ['quotes.view', 'files.view']);
		const aware = access(['core.quotes', 'core.jobs'], ['files.view', 'jobs.view']);
		const differences = compareAccess(legacy, aware, contractor, families);
		expect(differences.features.find((c) => c.key === 'core.quotes')?.direction).toBe('gained');
		expect(differences.permissions.find((c) => c.key === 'jobs.view')?.direction).toBe('gained');
		const lostWithoutReason = compareAccess(
			access(['core.quotes'], ['files.view']),
			access(['core.quotes'], []),
			contractor,
			families
		);
		expect(lostWithoutReason.permissions[0].cause).toMatch(/cannot explain/);
	});
});
