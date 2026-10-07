import { describe, expect, it } from 'vitest';
import type { EffectiveOrganizationAccess } from './effective';
import { contractorNavigation } from './navigation';

// The permission map already has the package folded in, as the resolver builds it; only the fields the
// menu reads are filled.
function accessWith(features: string[], permissions: string[]) {
	return {
		features: Object.fromEntries(features.map((key) => [key, true])),
		permissions: Object.fromEntries(permissions.map((key) => [key, true])),
		permission_scopes: {}
	} as unknown as EffectiveOrganizationAccess;
}

const everyCoreFeature = [
	'core.customers_properties',
	'core.requests_assessments',
	'core.quotes',
	'core.jobs',
	'core.schedule',
	'core.invoices_payments'
];
const ownerPermissions = [
	'customers.view',
	'requests.view',
	'quotes.view',
	'jobs.view',
	'invoices.view',
	'files.view',
	'pipeline.view',
	'marketing.view',
	'reviews.view',
	'conversations.view_team'
];

describe('contractorNavigation', () => {
	it('opens every core area to an owner on a full package and keeps unsold extras closed', () => {
		const navigation = contractorNavigation(accessWith(everyCoreFeature, ownerPermissions));
		expect(navigation).toMatchObject({
			schedule: true,
			clients: true,
			requests: true,
			jobs: true,
			quotes: true,
			invoices: true,
			files: true,
			inbox: false,
			pipeline: false,
			marketing: false,
			reviews: false
		});
	});

	it('leaves Quotes out of the menu when the package leaves Quotes out, whatever the role', () => {
		const features = everyCoreFeature.filter((key) => key !== 'core.quotes');
		const navigation = contractorNavigation(accessWith(features, ownerPermissions));
		expect(navigation.quotes).toBe(false);
		expect(navigation.jobs).toBe(true);
		expect(navigation.invoices).toBe(true);
	});

	it('shows the calendar only with Scheduling in the package', () => {
		const features = everyCoreFeature.filter((key) => key !== 'core.schedule');
		expect(contractorNavigation(accessWith(features, ownerPermissions)).schedule).toBe(false);
	});

	it('shows the Inbox only when the package sells it and the member may see conversations', () => {
		const features = [...everyCoreFeature, 'communications.inbox'];
		expect(contractorNavigation(accessWith(features, ownerPermissions)).inbox).toBe(true);
		expect(contractorNavigation(accessWith(features, ['customers.view'])).inbox).toBe(false);
	});

	it('follows the role inside the package: a field member without quotes.view sees no Quotes', () => {
		const navigation = contractorNavigation(
			accessWith(everyCoreFeature, ['jobs.view', 'requests.view'])
		);
		expect(navigation).toMatchObject({
			quotes: false,
			invoices: false,
			clients: false,
			jobs: true,
			schedule: true
		});
	});
});
