import { buildSetupCatalogue, type SetupCatalogueRow } from '$lib/setup/catalogue';

// Setup version 1 as public.setup_published_catalogue() returns it — the questions seeded by
// supabase/migrations/20261007100000_setup_questions_versioned.sql. For tests only.

type Item = SetupCatalogueRow['stages'][number]['items'][number];

const heading = (label: string, hint: string): Item => ({
	type: 'heading',
	fact_key: null,
	label,
	hint,
	built_in: false,
	required: false,
	can_defer: false,
	kind: null,
	options: null,
	max_length: null
});

const builtIn = (
	fact_key: string,
	label: string,
	options: { hint?: string; required?: boolean; canDefer?: boolean } = {}
): Item => ({
	type: 'question',
	fact_key,
	label,
	hint: options.hint ?? null,
	built_in: true,
	required: options.required ?? true,
	can_defer: options.canDefer ?? false,
	kind: null,
	options: null,
	max_length: null
});

export const SETUP_VERSION_1: SetupCatalogueRow = {
	version_id: '00000000-0000-4000-8000-000000000001',
	stages: [
		{
			key: 'business',
			title: 'Your business',
			description: 'The name, people and contact details Uplift builds everything else around.',
			service_key: null,
			items: [
				heading(
					'Business identity',
					'How your business is known. Plain facts are enough — Uplift writes the polished wording.'
				),
				builtIn('business.public_name', 'Business name customers know you by', {
					hint: 'Exactly as it appears on your van, cards or signs.'
				}),
				builtIn('business.legal_name', 'Legal name, if different', {
					hint: 'Leave empty if it is the same as the name above.',
					required: false
				}),
				builtIn('business.trade', 'Trade'),
				builtIn('business.type', 'Type of business'),
				heading(
					'Who Uplift talks to',
					'The person we contact during setup, and who gives the final go-ahead before launch.'
				),
				builtIn('business.contact_name', 'Main contact name'),
				builtIn('business.contact_email', 'Main contact email'),
				builtIn('business.contact_phone', 'Main contact phone'),
				builtIn('business.approver_name', 'Final approver name, if someone else', {
					hint: 'Leave empty if the main contact approves the finished work.',
					required: false
				}),
				builtIn('business.approver_email', 'Final approver email', { required: false }),
				heading(
					'How customers reach you',
					'The phone and email shown to customers. No business number or address yet? Say so and Uplift will help.'
				),
				builtIn('business.public_phone', 'Public phone number', { canDefer: true }),
				builtIn('business.public_email', 'Public email address', { canDefer: true }),
				heading(
					'Where you’re based',
					'Where you run the business from — your home is fine. It stays private unless you say otherwise.'
				),
				builtIn('business.country', 'Country'),
				builtIn('business.address_line1', 'Street address', { canDefer: true }),
				builtIn('business.address_line2', 'Flat, unit or suite, if any', { required: false }),
				builtIn('business.address_city', 'Town or city'),
				builtIn('business.address_region', 'State, province or county', { required: false }),
				builtIn('business.address_postal_code', 'Postcode or ZIP code'),
				builtIn('business.address_customers_visit', 'Do customers come to this address?', {
					hint: 'A shop, showroom or office counts. A home you only work out from does not.'
				}),
				builtIn('business.address_public', 'Can this address be shown publicly?', {
					hint: 'If you keep it private, customers only see your town and the areas you cover.'
				}),
				heading(
					'Language, time and money',
					'How words, times and prices appear across your system. Check each one — none of them becomes your default until you have confirmed it here.'
				),
				builtIn('business.language', 'Language your customers read', {
					hint: 'Uplift writes your website and customer messages in this language.'
				}),
				builtIn('business.timezone', 'Time zone', {
					hint: 'Sets the times on your schedule, bookings and reminders.'
				}),
				builtIn('business.currency', 'Currency you charge in', {
					hint: 'Used on every quote, invoice and payment.'
				}),
				heading(
					'Opening hours',
					'When customers can reach you. Uplift uses these on your website, your Google profile and your reminders.'
				),
				builtIn('business.hours', 'Normal weekly hours'),
				builtIn('business.hours_exceptions', 'Holidays and one-off days', {
					hint: 'Days in the next year when you are closed or keep different hours — public holidays, Christmas week, a planned break.',
					required: false
				}),
				{
					type: 'question',
					fact_key: 'business.hours_seasonal',
					label: 'Seasonal changes, if any',
					hint: 'For example: closed in January, or longer hours from June to August.',
					built_in: false,
					required: false,
					can_defer: false,
					kind: 'longtext',
					options: null,
					max_length: 500
				}
			]
		}
	]
};

export const SETUP_CATALOGUE_1 = buildSetupCatalogue(SETUP_VERSION_1);
