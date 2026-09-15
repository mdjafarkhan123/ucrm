// The getting-started checklist shown to a new organization's owner/admin. Every item is derived from real
// data -- never a flag someone can tick by hand -- so the list can never say something is done when it
// is not.

export type OnboardingChecklistItem = {
	key: 'business_profile' | 'price_book' | 'first_client' | 'invite_team';
	label: string;
	description: string;
	complete: boolean;
};

export type OnboardingChecklistFacts = {
	businessProfileComplete: boolean;
	hasCatalogItem: boolean;
	hasClient: boolean;
	teamInvited: boolean;
};

export function computeOnboardingChecklist(facts: OnboardingChecklistFacts) {
	const items: OnboardingChecklistItem[] = [
		{
			key: 'business_profile',
			label: 'Complete your business profile',
			description: 'Add your business name, timezone, and currency.',
			complete: facts.businessProfileComplete
		},
		{
			key: 'price_book',
			label: 'Add your price book',
			description: 'List the products and services you charge for.',
			complete: facts.hasCatalogItem
		},
		{
			key: 'first_client',
			label: 'Add your first customer',
			description: 'Create a customer record to start their job history.',
			complete: facts.hasClient
		},
		{
			key: 'invite_team',
			label: 'Invite your team',
			description: 'Bring in the people who will use the CRM with you.',
			complete: facts.teamInvited
		}
	];

	return { items, allComplete: items.every((item) => item.complete) };
}
