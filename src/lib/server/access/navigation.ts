import type { EffectiveOrganizationAccess } from './effective';
import { hasPermission } from './permission';
import type { ContractorNavigation } from '$lib/account/navigation';

// Each answer is the same check the page's own list route makes, read from the access the shell resolved
// once, so the menu is drawn complete on the first paint and never offers a page that would only refuse.
export function contractorNavigation(access: EffectiveOrganizationAccess): ContractorNavigation {
	const can = (permissionKey: string) => hasPermission(access, permissionKey);
	return {
		// The calendar is read through jobs.view (`/api/schedule`) and only exists with Scheduling.
		schedule: access.features['core.schedule'] === true && can('jobs.view'),
		// Mirrors `/api/communications/email-history?access=1`: the shared inbox is sold separately.
		inbox:
			access.features['communications.inbox'] === true &&
			(can('conversations.view_team') || can('conversations.view_assigned')),
		clients: can('customers.view'),
		requests: can('requests.view'),
		pipeline: can('pipeline.view'),
		jobs: can('jobs.view'),
		quotes: can('quotes.view'),
		invoices: can('invoices.view'),
		files: can('files.view'),
		marketing: can('marketing.view'),
		reviews: can('reviews.view')
	};
}
