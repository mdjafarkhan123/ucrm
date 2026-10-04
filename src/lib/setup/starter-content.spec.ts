import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { SETUP_VERSION_1 } from './catalogue.fixture';
import {
	BUILT_IN_FACTS,
	buildSetupCatalogue,
	catalogueFacts,
	sectionFacts,
	shownFacts,
	type SetupAnswers,
	type SetupCatalogueRow
} from './catalogue';
import { followUpSuggestions } from './follow-ups';
import { COUNTRIES } from '../settings/countries';
import { setupAnswersSchema } from '../server/validation/setup.schema';
import {
	catalogueForServices,
	missingRequiredFacts,
	setupAnswerShortfall,
	shownCatalogueFacts
} from './catalogue';

// B3b–B12 load the approved starter content (docs/client-onboarding-setup-content-blueprint.md) into the setup
// draft through private.setup_load_starter_stage. The database cannot check a "show only if" rule against a
// built-in question's choices, which live in code, so these tests read each stage straight from its migration.

type Item = SetupCatalogueRow['stages'][number]['items'][number];

const MIGRATIONS = 'supabase/migrations';
const STAGE_CALL =
	/select private\.setup_load_starter_stage\(\s*'([a-z_]+)',\s*'([^']+)',\s*'([^']+)',\s*(null|'[a-z_]+'),\s*\$items\$([\s\S]*?)\$items\$::jsonb/g;

function starterStages(): SetupCatalogueRow['stages'] {
	const stages = new Map<string, SetupCatalogueRow['stages'][number]>();
	for (const file of readdirSync(MIGRATIONS).sort()) {
		if (!file.includes('_setup_starter_')) continue;
		for (const [, key, title, description, service, json] of readFileSync(
			`${MIGRATIONS}/${file}`,
			'utf8'
		).matchAll(STAGE_CALL)) {
			const items = (JSON.parse(json) as Partial<Item>[]).map((item): Item => ({
				fact_key: null,
				hint: null,
				built_in: false,
				required: false,
				can_defer: false,
				kind: null,
				options: null,
				max_length: null,
				...item,
				type: item.type ?? 'question',
				label: item.label ?? ''
			}));
			stages.set(key, {
				key,
				title,
				description,
				service_key: service === 'null' ? null : service.slice(1, -1),
				items
			});
		}
	}
	return [...stages.values()];
}

const stages = starterStages();
const starter = buildSetupCatalogue({ version_id: 'starter', stages });
const facts = catalogueFacts(starter);
const have = (value: string) => ({ availability: 'have' as const, value, note: null });

describe('starter setup content', () => {
	it('loads every stage built so far', () => {
		expect(stages.map((stage) => stage.key)).toEqual([
			'business',
			'services',
			'brand',
			'website',
			'google',
			'calls',
			'texting',
			'reviews',
			'crm',
			'import',
			'marketing'
		]);
	});

	it('leaves no question out for want of answer rules', () => {
		const questions = stages.flatMap((stage) =>
			stage.items.filter((item) => item.type === 'question')
		);
		expect(facts.size).toBe(questions.length);
		for (const item of questions)
			if (item.built_in) expect(BUILT_IN_FACTS[item.fact_key!], item.fact_key!).toBeDefined();
	});

	it('keeps every text limit within what the database allows', () => {
		for (const stage of stages)
			for (const item of stage.items)
				if (item.max_length !== null)
					expect(item.max_length, item.fact_key!).toBeLessThanOrEqual(2000);
	});

	it('only reuses questions that are always asked, as the database requires', () => {
		const items = new Map(
			stages.flatMap((stage) => stage.items.map((item) => [item.fact_key, item]))
		);
		for (const item of items.values())
			if (item.kind === 'reuse')
				expect(items.get(item.reuse_from!)?.show_if ?? null, item.fact_key!).toBeNull();
	});

	it('only shows a question for answers its earlier question can give', () => {
		for (const fact of facts.values())
			for (const condition of fact.showIf ?? []) {
				if (!('values' in condition)) continue;
				const source = facts.get(condition.factKey);
				expect(source, `${fact.key} depends on ${condition.factKey}`).toBeDefined();
				const choices =
					source!.kind === 'country'
						? COUNTRIES.map((country) => country.value)
						: (source!.options?.map((option) => option.value) ?? []);
				for (const value of condition.values) expect(choices, fact.key).toContain(value);
			}
	});

	it('still asks every question clients answered in version 1, so their answers show again', () => {
		const before = catalogueFacts(buildSetupCatalogue(SETUP_VERSION_1));
		for (const [key, fact] of before) {
			expect(facts.has(key), key).toBe(true);
			expect(facts.get(key)!.kind, key).toBe(fact.kind);
		}
	});

	describe('Your business', () => {
		const business = starter.sections.find((section) => section.key === 'business')!;
		const shown = (answers: SetupAnswers) => shownFacts(sectionFacts(business), answers);

		it('asks the legal name only when it differs', () => {
			expect(shown({}).has('business.legal_name')).toBe(false);
			expect(shown({ 'business.legal_name_differs': have('no') }).has('business.legal_name')).toBe(
				false
			);
			expect(shown({ 'business.legal_name_differs': have('yes') }).has('business.legal_name')).toBe(
				true
			);
		});

		it('asks for the final approver only when the main contact is not the one', () => {
			const approver = [
				'business.approver_name',
				'business.approver_email',
				'business.approver_phone'
			];
			const whenYes = shown({ 'business.contact_is_approver': have('yes') });
			const whenNo = shown({ 'business.contact_is_approver': have('no') });
			for (const key of approver) {
				expect(whenYes.has(key)).toBe(false);
				expect(whenNo.has(key)).toBe(true);
			}
		});

		it('asks whether the address may be public only when customers visit it', () => {
			expect(
				shown({ 'business.address_customers_visit': have('no') }).has('business.address_public')
			).toBe(false);
			expect(
				shown({ 'business.address_customers_visit': have('yes') }).has('business.address_public')
			).toBe(true);
		});

		it('asks for weekly hours only for set opening hours, and after hours unless always open', () => {
			const always = shown({ 'business.availability': have('always') });
			expect(always.has('business.hours')).toBe(false);
			expect(always.has('business.after_hours')).toBe(false);
			const set = shown({ 'business.availability': have('set_hours') });
			expect(set.has('business.hours')).toBe(true);
			expect(set.has('business.after_hours')).toBe(true);
		});

		it('shows an earlier client their old legal name, approver and hours again from the suggestions', () => {
			const old: SetupAnswers = {
				'business.public_name': have('Raad LTD'),
				'business.legal_name': have('Raad Trading Limited'),
				'business.approver_name': have('Sam Lee'),
				'business.hours': have('{"days":[]}')
			};
			const suggested = Object.fromEntries(
				Object.entries(followUpSuggestions(old, null)).flatMap(([key, value]) =>
					value ? [[key, have(value)]] : []
				)
			);
			const asked = shown({ ...old, ...suggested });
			for (const key of ['business.legal_name', 'business.approver_name', 'business.hours'])
				expect(asked.has(key), key).toBe(true);
		});
	});

	describe('Services and service area', () => {
		const services = starter.sections.find((section) => section.key === 'services')!;
		const shown = (answers: SetupAnswers) => shownFacts(sectionFacts(services), answers);
		const withServices: SetupAnswers = {
			'services.offered': have(
				'[{"id":"a1","values":{"name":"Boiler repair","season":"all_year"}}]'
			)
		};

		it('is shown to everyone', () => {
			expect(services.serviceKey).toBeNull();
		});

		it('picks services and places from the lists the client filled in, by name', () => {
			for (const [key, list] of [
				['services.promoted', 'services.offered'],
				['services.urgent_services', 'services.offered'],
				['area.promoted', 'area.places']
			]) {
				const fact = facts.get(key)!;
				expect(fact.kind, key).toBe('pick');
				expect(fact.pickFrom, key).toBe(list);
				expect(fact.pickNameKey, key).toBe('name');
			}
			expect(facts.get('services.promoted')).toMatchObject({
				minChoices: 3,
				maxChoices: 5,
				ordered: true
			});
		});

		it('confirms the town from Your business instead of asking it again', () => {
			const city = facts.get('area.base_city')!;
			expect(city.reuseFrom).toBe('business.address_city');
			expect(city.reuseSection?.key).toBe('business');
		});

		it('asks each follow-up only after its yes', () => {
			for (const [gate, followUp] of [
				['services.urgent', 'services.urgent_services'],
				['services.credentials_needed', 'services.credentials'],
				['services.public_prices', 'services.prices'],
				['area.other_locations', 'area.locations']
			]) {
				expect(shown({ ...withServices, [gate]: have('no') }).has(followUp), followUp).toBe(false);
				expect(shown({ ...withServices, [gate]: have('yes') }).has(followUp), followUp).toBe(true);
			}
		});

		it('asks for the furthest distance or the longest travel time only when that sets the limit', () => {
			const byPlaces = shown({ 'area.limit_type': have('places') });
			const byDistance = shown({ 'area.limit_type': have('distance') });
			const byTime = shown({ 'area.limit_type': have('travel_time') });
			expect(byPlaces.has('area.max_distance') || byPlaces.has('area.max_travel_time')).toBe(false);
			expect(byDistance.has('area.max_distance')).toBe(true);
			expect(byDistance.has('area.max_travel_time')).toBe(false);
			expect(byTime.has('area.max_travel_time')).toBe(true);
			expect(byTime.has('area.max_distance')).toBe(false);
			for (const answers of [byPlaces, byDistance, byTime])
				expect(answers.has('area.places')).toBe(true);
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const services20 = Array.from({ length: 20 }, (_, n) => ({
				id: `s${n}`,
				values: {
					name: `Boiler repair and servicing ${n}`,
					note: 'Gas and oil boilers, all makes',
					season: 'all_year'
				}
			}));
			const sent: Record<string, string> = {
				'services.offered': JSON.stringify(services20),
				'services.promoted': JSON.stringify(['s3', 's0', 's7']),
				'services.not_offered': JSON.stringify([{ id: 'n1', values: { name: 'Solar panels' } }]),
				'services.customer_type': 'both',
				'services.urgent': 'yes',
				'services.urgent_services': JSON.stringify(['s0']),
				'services.credentials_needed': 'no',
				'services.public_prices': 'yes',
				'services.prices': JSON.stringify([
					{
						id: 'p1',
						values: {
							service: 'Call-out',
							price_type: 'minimum',
							amount: { amount: '85', currency: 'GBP' }
						}
					}
				]),
				'area.base_city': JSON.stringify({ same_as: 'business.address_city' }),
				'area.limit_type': 'distance',
				'area.places': JSON.stringify([
					{ id: 'a1', values: { name: 'Leeds' } },
					{ id: 'a2', values: { name: 'Bradford' } }
				]),
				'area.max_distance': JSON.stringify({ amount: 25, unit: 'mi' }),
				'area.excluded': JSON.stringify([{ id: 'x1', values: { name: 'Ilkley' } }]),
				'area.promoted': JSON.stringify(['a2', 'a1']),
				'area.other_locations': 'no'
			};
			const earlier: SetupAnswers = { 'business.address_city': have('Leeds') };
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			// Coming back reads each stored value as the text the page holds (src/lib/server/setup/read.ts).
			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				expect(JSON.stringify(stored).length, answer.fact_key).toBeLessThan(8000);
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(JSON.parse(resumed['services.offered']!.value!)).toEqual(services20);
			expect(JSON.parse(resumed['area.excluded']!.value!)).toEqual([
				{ id: 'x1', values: { name: 'Ilkley' } }
			]);
			const asked = shown(resumed);
			expect(missingRequiredFacts(services, resumed, asked)).toEqual([]);
			for (const fact of sectionFacts(services))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});

		it('lets a client without their service area yet still send the setup', () => {
			expect(facts.get('area.places')!.canDefer).toBe(true);
			const deferred = shown({
				'area.places': { availability: 'not_yet', value: null, note: null }
			});
			expect(deferred.has('area.promoted')).toBe(false);
		});
	});

	describe('Brand, photos and proof', () => {
		const brand = starter.sections.find((section) => section.key === 'brand')!;
		const shown = (answers: SetupAnswers) => shownFacts(sectionFacts(brand), answers);
		const fileId = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
		const save = (sent: Record<string, string>) =>
			setupAnswersSchema(facts).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
		// The least a client with no logo, no photos and no financing gives.
		const bare: Record<string, string> = {
			'brand.logo_status': 'none',
			'photos.have': 'no',
			'proof.payment_methods': JSON.stringify(['cash', 'bank_transfer']),
			'proof.financing': 'no',
			'proof.reasons': JSON.stringify([{ id: 'r1', values: { reason: 'We reply within 2 hours' } }])
		};
		const asAnswers = (sent: Record<string, string>): SetupAnswers =>
			Object.fromEntries(Object.entries(sent).map(([key, value]) => [key, have(value)]));

		it('is shown to everyone', () => {
			expect(brand.serviceKey).toBeNull();
		});

		it('never makes a client without a logo or photos stop', () => {
			expect(save(bare).error?.issues ?? []).toEqual([]);
			const answers = asAnswers(bare);
			expect(missingRequiredFacts(brand, answers, shown(answers))).toEqual([]);
		});

		it('asks for logo files, or who has them, only on that branch', () => {
			const upload = shown({ 'brand.logo_status': have('upload') });
			expect(upload.has('brand.logo_files')).toBe(true);
			expect(upload.has('brand.logo_owned')).toBe(true);
			expect(upload.has('brand.logo_holder')).toBe(false);
			const elsewhere = shown({ 'brand.logo_status': have('someone_else') });
			expect(elsewhere.has('brand.logo_holder')).toBe(true);
			expect(elsewhere.has('brand.logo_files')).toBe(false);
			for (const status of ['need_help', 'none']) {
				const asked = shown({ 'brand.logo_status': have(status) });
				expect(asked.has('brand.logo_files') || asked.has('brand.logo_holder'), status).toBe(false);
			}
		});

		it('lets the logo files and who has them wait without blocking', () => {
			expect(facts.get('brand.logo_files')!.canDefer).toBe(true);
			expect(facts.get('brand.logo_holder')!.canDefer).toBe(true);
			expect(facts.get('photos.uploads')!.canDefer).toBe(true);
		});

		it('asks about photos only after the client says they have some', () => {
			for (const key of ['photos.kinds', 'photos.uploads']) {
				expect(shown({ 'photos.have': have('no') }).has(key), key).toBe(false);
				expect(shown({ 'photos.have': have('yes') }).has(key), key).toBe(true);
			}
			expect(shown({ 'proof.financing': have('no') }).has('proof.financing_details')).toBe(false);
			expect(shown({ 'proof.financing': have('yes') }).has('proof.financing_details')).toBe(true);
		});

		it('records, for every photo, private details and permission to publish', () => {
			const fields = facts.get('photos.uploads')!.listFields!;
			for (const key of ['photo', 'private_details', 'may_publish'])
				expect(fields.find((field) => field.key === key)?.required, key).toBe(true);
		});

		it('saves a logo and 20 captioned photos and shows them again', () => {
			const photos = Array.from({ length: 20 }, (_, n) => ({
				id: `p${n}`,
				values: {
					photo: fileId(n + 10),
					caption: `Kitchen rewire and new consumer unit in a 1930s semi, finished in two days ${n}`,
					private_details: 'no',
					may_publish: 'yes'
				}
			}));
			const sent = {
				...bare,
				'brand.logo_status': 'upload',
				'brand.logo_files': JSON.stringify([fileId(1), fileId(2)]),
				'brand.logo_owned': 'yes',
				'brand.colours': JSON.stringify(['#1a73e8', '#FFFFFF']),
				'brand.feel': JSON.stringify(['dependable', 'friendly', 'Local and family-run']),
				'photos.have': 'yes',
				'photos.kinds': JSON.stringify(['completed_work', 'vehicles']),
				'photos.uploads': JSON.stringify(photos),
				'proof.years': '12',
				'proof.social': JSON.stringify([
					{ id: 's1', values: { platform: 'facebook', url: 'facebook.com/raadltd' } }
				])
			};
			const parsed = save(sent);
			expect(parsed.error?.issues ?? []).toEqual([]);
			const resumed: SetupAnswers = {};
			for (const answer of parsed.data!.answers)
				resumed[answer.fact_key] = have(
					typeof answer.value === 'string' ? answer.value : JSON.stringify(answer.value)
				);
			expect(JSON.parse(resumed['photos.uploads']!.value!)).toEqual(photos);
			expect(JSON.parse(resumed['brand.colours']!.value!)).toEqual(['#1A73E8', '#FFFFFF']);
			expect(missingRequiredFacts(brand, resumed, shown(resumed))).toEqual([]);
		});

		it('refuses a list too long to store in plain words, not with a database error', () => {
			const reviews = Array.from({ length: 10 }, (_, n) => ({
				id: `t${n}`,
				values: { quote: 'Brilliant work. '.repeat(70), name: `Customer ${n}`, permission: 'yes' }
			}));
			const parsed = save({ 'proof.testimonials': JSON.stringify(reviews) });
			expect(parsed.error?.issues.map((issue) => issue.message)).toEqual([
				'This is too long to save. Shorten some entries or remove a few.'
			]);
		});
	});

	describe('Website and domain', () => {
		const website = starter.sections.find((section) => section.key === 'website')!;
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);
		const situation = (value: string) => shown({ 'domain.situation': have(value) });
		const branchOnly = {
			own: ['domain.owner_email'],
			someone_else: ['domain.controller', 'domain.controller_can_help'],
			buy: ['domain.wishlist'],
			unsure: ['domain.unsure_notes']
		};
		const existingDomain = [
			'domain.name',
			'domain.registrar',
			'domain.renewal_by',
			'domain.dns_by',
			'domain.email_uses',
			'domain.other_uses'
		];

		it('is shown only to a package with the website', () => {
			expect(website.serviceKey).toBe('website');
		});

		it('asks each domain branch only its own questions', () => {
			const all = Object.values(branchOnly).flat();
			for (const [branch, own] of Object.entries(branchOnly)) {
				const asked = situation(branch);
				for (const key of all) expect(asked.has(key), `${branch}: ${key}`).toBe(own.includes(key));
				const hasDomain = branch === 'own' || branch === 'someone_else';
				for (const key of existingDomain)
					expect(asked.has(key), `${branch}: ${key}`).toBe(hasDomain);
			}
		});

		it('never asks for a password', () => {
			for (const fact of sectionFacts(website)) {
				expect(fact.key).not.toMatch(/password/);
				for (const field of fact.listFields ?? []) expect(field.key).not.toMatch(/password/);
				expect(fact.label).not.toMatch(/password/i);
			}
		});

		it('asks the email company and the extra uses only after their answer', () => {
			const base = { 'domain.situation': have('own') };
			for (const value of ['yes', 'not_sure'])
				expect(
					shown({ ...base, 'domain.email_uses': have(value) }).has('domain.email_provider')
				).toBe(true);
			expect(shown({ ...base, 'domain.email_uses': have('no') }).has('domain.email_provider')).toBe(
				false
			);
			expect(
				shown({ ...base, 'domain.other_uses': have('yes') }).has('domain.other_uses_list')
			).toBe(true);
			expect(
				shown({ ...base, 'domain.other_uses': have('not_sure') }).has('domain.other_uses_list')
			).toBe(false);
		});

		it('confirms the phone, email and reasons given earlier instead of asking again', () => {
			for (const [key, source] of [
				['website.phone', 'business.public_phone'],
				['website.email', 'business.public_email'],
				['website.reasons', 'proof.reasons']
			])
				expect(facts.get(key)!.reuseFrom, key).toBe(source);
		});

		it('picks different featured services and places only when the promoted ones are not right', () => {
			const lists: SetupAnswers = {
				'services.offered': have(
					'[{"id":"s1","values":{"name":"Boiler repair","season":"all_year"}}]'
				),
				'area.places': have('[{"id":"a1","values":{"name":"Leeds"}}]')
			};
			const same = shown({ ...lists, 'website.featured_same': have('yes') });
			const different = shown({ ...lists, 'website.featured_same': have('no') });
			for (const key of ['website.featured_services', 'website.featured_places']) {
				expect(same.has(key), key).toBe(false);
				expect(different.has(key), key).toBe(true);
			}
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const earlier: SetupAnswers = {
				'business.public_phone': have('+44 113 496 0000'),
				'business.public_email': have('hello@raadplumbing.co.uk'),
				'services.offered': have(
					'[{"id":"s1","values":{"name":"Boiler repair","season":"all_year"}}]'
				),
				'area.places': have('[{"id":"a1","values":{"name":"Leeds"}}]'),
				'proof.reasons': have('[{"id":"r1","values":{"reason":"We reply within 2 hours"}}]')
			};
			const sent: Record<string, string> = {
				'domain.situation': 'someone_else',
				'domain.name': 'raadplumbing.co.uk',
				'domain.registrar': '123 Reg',
				'domain.controller': JSON.stringify([
					{
						id: 'c1',
						values: { name: 'Sam Webb', company: 'Webb Design', email: 'sam@webb.example' }
					}
				]),
				'domain.controller_can_help': 'yes',
				'domain.renewal_by': JSON.stringify([{ id: 'r1', values: { name: 'Webb Design' } }]),
				'domain.dns_by': JSON.stringify([{ id: 'd1', values: { name: '123 Reg' } }]),
				'domain.email_uses': 'yes',
				'domain.email_provider': 'Microsoft 365',
				'domain.other_uses': 'yes',
				'domain.other_uses_list': JSON.stringify([
					{ id: 'o1', values: { what: 'Booking page', url: 'book.raadplumbing.co.uk' } }
				]),
				'website.live_now': 'yes',
				'website.live_url': 'raadplumbing.co.uk',
				'website.host': 'Wix',
				'website.main_action': 'quote',
				'website.second_action': 'call',
				'website.form_recipients': JSON.stringify([
					{ id: 'f1', values: { name: 'Office', email: 'office@raadplumbing.co.uk' } }
				]),
				'website.phone': JSON.stringify({ same_as: 'business.public_phone' }),
				'website.email': 'enquiries@raadplumbing.co.uk',
				'website.featured_same': 'no',
				'website.featured_services': JSON.stringify(['s1']),
				'website.featured_places': JSON.stringify(['a1']),
				'website.reasons': JSON.stringify({ same_as: 'proof.reasons' }),
				'website.show_proof': 'yes',
				'website.process': JSON.stringify(
					['You call', 'We visit and measure', 'Written quote in 2 days', 'Work booked'].map(
						(step, n) => ({ id: `p${n}`, values: { step } })
					)
				),
				'website.keep_any': 'no',
				'website.extra_pages': JSON.stringify(['about', 'projects', 'Boiler grants'])
			};
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(JSON.parse(resumed['domain.controller']!.value!)[0].values.company).toBe(
				'Webb Design'
			);
			expect(missingRequiredFacts(website, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(website))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});

		it('lets a client who has to buy a domain send the setup with only the website basics', () => {
			const answers: SetupAnswers = {
				'business.public_phone': have('+44 113 496 0000'),
				'business.public_email': have('hello@raadplumbing.co.uk'),
				'proof.reasons': have('[{"id":"r1","values":{"reason":"Local for 20 years"}}]'),
				'domain.situation': have('buy'),
				'website.live_now': have('no'),
				'website.main_action': have('call'),
				'website.form_recipients': have(
					'[{"id":"f1","values":{"name":"Me","email":"me@example.com"}}]'
				),
				'website.phone': have('{"same_as":"business.public_phone"}'),
				'website.email': have('{"same_as":"business.public_email"}'),
				'website.featured_same': have('yes'),
				'website.reasons': have('{"same_as":"proof.reasons"}'),
				'website.show_proof': have('yes'),
				'website.process': { availability: 'not_yet', value: null, note: null },
				'website.keep_any': have('no')
			};
			expect(missingRequiredFacts(website, answers, shown(answers))).toEqual([]);
		});
	});
	describe('Google Business Profile', () => {
		const google = starter.sections.find((section) => section.key === 'google')!;
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);
		const situation = (value: string) => shown({ 'gbp.situation': have(value) });

		it('is shown only to a package with Google Business Profile management', () => {
			expect(google.serviceKey).toBe('google_profile');
		});

		it('asks each starting answer only its own questions', () => {
			const branchOnly: Record<string, string[]> = {
				own: ['gbp.link', 'gbp.manager_by'],
				someone_else: ['gbp.link', 'gbp.controller', 'gbp.manager_by'],
				need_new: ['gbp.owner_account'],
				unsure: ['gbp.link']
			};
			const all = new Set(Object.values(branchOnly).flat());
			for (const [branch, own] of Object.entries(branchOnly)) {
				const asked = situation(branch);
				for (const key of all) expect(asked.has(key), `${branch}: ${key}`).toBe(own.includes(key));
			}
		});

		it('never asks for a password', () => {
			for (const fact of sectionFacts(google)) {
				expect(fact.key).not.toMatch(/password/);
				for (const field of fact.listFields ?? []) expect(field.key).not.toMatch(/password/);
				expect(fact.label).not.toMatch(/password/i);
			}
		});

		it('confirms the name, phone, opening date and areas given earlier instead of asking again', () => {
			for (const [key, source] of [
				['gbp.public_name', 'business.public_name'],
				['gbp.phone', 'business.public_phone'],
				['gbp.opening_date', 'business.started_on'],
				['gbp.service_areas', 'area.places']
			])
				expect(facts.get(key)!.reuseFrom, key).toBe(source);
		});

		it('asks for service areas only when the client goes to customers', () => {
			const model = (value: string) =>
				shown({ 'gbp.business_model': have(value) }).has('gbp.service_areas');
			expect(model('storefront')).toBe(false);
			expect(model('service_area')).toBe(true);
			expect(model('both')).toBe(true);
		});

		it('asks for other hours, another address and past details only after their answer', () => {
			expect(shown({ 'gbp.hours_same': have('no') }).has('gbp.hours')).toBe(true);
			expect(shown({ 'gbp.hours_same': have('yes') }).has('gbp.hours')).toBe(false);
			expect(shown({ 'gbp.verify_same': have('no') }).has('gbp.verify_address')).toBe(true);
			expect(shown({ 'gbp.verify_same': have('yes') }).has('gbp.verify_address')).toBe(false);
			for (const [question, follow] of [
				['gbp.history', 'gbp.history_details'],
				['gbp.duplicates', 'gbp.duplicate_list']
			]) {
				expect(shown({ [question]: have('yes') }).has(follow), follow).toBe(true);
				expect(shown({ [question]: have('not_sure') }).has(follow), follow).toBe(true);
				expect(shown({ [question]: have('no') }).has(follow), follow).toBe(false);
			}
		});

		it('asks about photos only when the client shared some', () => {
			expect(shown({ 'photos.have': have('yes') }).has('gbp.photos_ok')).toBe(true);
			expect(shown({ 'photos.have': have('no') }).has('gbp.photos_ok')).toBe(false);
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const earlier: SetupAnswers = {
				'business.public_name': have('Raad Plumbing'),
				'business.public_phone': have('+44 113 496 0000'),
				'business.started_on': have('2012-04-01'),
				'area.places': have('[{"id":"a1","values":{"name":"Leeds"}}]'),
				'photos.have': have('yes')
			};
			const sent: Record<string, string> = {
				'gbp.situation': 'someone_else',
				'gbp.link': 'https://maps.app.goo.gl/abc123',
				'gbp.controller': JSON.stringify([
					{ id: 'c1', values: { name: 'Sam Webb', company: 'Webb Marketing' } }
				]),
				'gbp.business_model': 'service_area',
				'gbp.public_name': JSON.stringify({ same_as: 'business.public_name' }),
				'gbp.other_names': 'Boiler servicing',
				'gbp.phone': JSON.stringify({ same_as: 'business.public_phone' }),
				'gbp.hours_same': 'no',
				'gbp.hours': 'Mon–Fri 8am–6pm, Sat 9am–1pm',
				'gbp.website': 'raadplumbing.co.uk',
				'gbp.opening_date': JSON.stringify({ same_as: 'business.started_on' }),
				'gbp.service_areas': JSON.stringify({ same_as: 'area.places' }),
				'gbp.photos_ok': 'yes',
				'gbp.verify_same': 'no',
				'gbp.verify_address': JSON.stringify([
					{ id: 'v1', values: { line1: '4 Mill Lane', city: 'Leeds', postal_code: 'LS1 4AB' } }
				]),
				'gbp.history': 'yes',
				'gbp.history_details': 'Suspended in 2022 after a move; reinstated.',
				'gbp.duplicates': 'not_sure',
				'gbp.duplicate_list': JSON.stringify([
					{ id: 'd1', values: { note: 'Old listing under the old shop name' } }
				]),
				'gbp.manager_by': 'controller'
			};
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(JSON.parse(resumed['gbp.verify_address']!.value!)[0].values.postal_code).toBe(
				'LS1 4AB'
			);
			expect(missingRequiredFacts(google, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(google))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});

		it('lets a client who needs a new profile send the setup without its Google account yet', () => {
			const answers: SetupAnswers = {
				'business.public_name': have('Raad Plumbing'),
				'business.public_phone': have('+44 113 496 0000'),
				'gbp.situation': have('need_new'),
				'gbp.owner_account': { availability: 'not_yet', value: null, note: null },
				'gbp.business_model': have('storefront'),
				'gbp.public_name': have('{"same_as":"business.public_name"}'),
				'gbp.phone': have('{"same_as":"business.public_phone"}'),
				'gbp.hours_same': have('yes'),
				'gbp.verify_same': have('yes'),
				'gbp.history': have('no'),
				'gbp.duplicates': have('no')
			};
			expect(missingRequiredFacts(google, answers, shown(answers))).toEqual([]);
		});
	});

	describe('Calls and phone number', () => {
		const calls = starter.sections.find((section) => section.key === 'calls')!;
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);
		const usa = { 'business.country': have('US') };

		it('is shown only to a package with Calls and texting', () => {
			expect(calls.serviceKey).toBe('calls_texting');
		});

		it('asks each number choice only its own questions', () => {
			const branchOnly: Record<string, string[]> = {
				new: ['calls.new_number_area'],
				keep: ['calls.existing_number', 'calls.keep_how'],
				advice: []
			};
			const all = new Set(Object.values(branchOnly).flat());
			for (const [branch, own] of Object.entries(branchOnly)) {
				const asked = shown({ 'calls.number_plan': have(branch) });
				for (const key of all) expect(asked.has(key), `${branch}: ${key}`).toBe(own.includes(key));
			}
		});

		it('offers texting from a kept number only in the USA and Canada, and never when it moves', () => {
			const kept = (country: string, how: string) =>
				shown({
					'business.country': have(country),
					'calls.number_plan': have('keep'),
					'calls.keep_how': have(how)
				}).has('calls.text_from_existing');
			expect(kept('US', 'forward')).toBe(true);
			expect(kept('CA', 'unsure')).toBe(true);
			expect(kept('US', 'move')).toBe(false);
			for (const country of ['GB', 'AU', 'IE', 'DE', 'FR'])
				expect(kept(country, 'forward'), country).toBe(false);
		});

		it('asks for the phone company details only when the number moves', () => {
			const port = [
				'calls.port_carrier',
				'calls.port_account',
				'calls.port_bill',
				'calls.port_approver'
			];
			for (const how of ['forward', 'move', 'unsure']) {
				const asked = shown({ 'calls.number_plan': have('keep'), 'calls.keep_how': have(how) });
				for (const key of port) expect(asked.has(key), `${how}: ${key}`).toBe(how === 'move');
			}
		});

		it('never asks for a password, PIN or one-time code', () => {
			const texting = starter.sections.find((section) => section.key === 'texting')!;
			for (const fact of [...sectionFacts(calls), ...sectionFacts(texting)]) {
				const secret = /password|(^|[._])pin($|_)|otp|one_time/;
				expect(fact.key).not.toMatch(secret);
				for (const field of fact.listFields ?? []) expect(field.key).not.toMatch(secret);
				expect(fact.label).not.toMatch(/password|\bPIN\b|one-time code/i);
			}
		});

		it('asks the ring order, backup, emergency phone and greeting only after their answer', () => {
			const people =
				'[{"id":"p1","values":{"name":"Sam","phone":"+15550100"}},{"id":"p2","values":{"name":"Ali","phone":"+15550101"}}]';
			expect(
				shown({ 'calls.ring_people': have(people), 'calls.ring_mode': have('in_order') }).has(
					'calls.ring_order'
				)
			).toBe(true);
			expect(
				shown({ 'calls.ring_people': have(people), 'calls.ring_mode': have('together') }).has(
					'calls.ring_order'
				)
			).toBe(false);
			for (const [question, value, follow] of [
				['calls.no_answer', 'backup', 'calls.backup'],
				['calls.hours_same', 'no', 'calls.hours'],
				['calls.after_hours', 'emergency', 'calls.emergency_phone'],
				['calls.voicemail_type', 'write', 'calls.voicemail_words'],
				['calls.voicemail_type', 'upload', 'calls.voicemail_recording'],
				['calls.missed_text', 'yes', 'calls.missed_text_words']
			]) {
				expect(shown({ [question]: have(value) }).has(follow), follow).toBe(true);
			}
			expect(shown({ 'calls.voicemail_type': have('standard') }).has('calls.voicemail_words')).toBe(
				false
			);
			expect(shown({ 'calls.missed_text': have('no') }).has('calls.missed_text_words')).toBe(false);
		});

		it('takes the bill for moving a number only as a protected document', () => {
			expect(facts.get('calls.port_bill')).toMatchObject({
				kind: 'protected_file',
				canDefer: true
			});
		});

		it('takes the voicemail greeting only as a voice recording', () => {
			expect(facts.get('calls.voicemail_recording')!.fileKinds).toEqual(['audio']);
		});

		it('confirms the language given earlier instead of asking again', () => {
			expect(facts.get('calls.language')!.reuseFrom).toBe('business.language');
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const earlier: SetupAnswers = {
				...usa,
				'business.language': have('English')
			};
			const sent: Record<string, string> = {
				'calls.number_plan': 'keep',
				'calls.existing_number': '+1 415 555 0100',
				'calls.keep_how': 'move',
				'calls.port_carrier': 'AT&T',
				'calls.port_account': JSON.stringify([
					{
						id: 'a1',
						values: { name: 'Sam Raad', line1: '12 Main St', city: 'Oakland', postal_code: '94607' }
					}
				]),
				'calls.port_bill': JSON.stringify(['00000000-0000-4000-8000-000000000001']),
				'calls.port_approver': JSON.stringify([
					{ id: 'b1', values: { name: 'Sam Raad', email: 'sam@example.com' } }
				]),
				'calls.ring_people': JSON.stringify([
					{ id: 'p1', values: { name: 'Sam', phone: '+1 415 555 0101' } },
					{ id: 'p2', values: { name: 'Office', phone: '+1 415 555 0102' } }
				]),
				'calls.ring_mode': 'in_order',
				'calls.ring_order': JSON.stringify(['p2', 'p1']),
				'calls.ring_time': '20',
				'calls.no_answer': 'backup',
				'calls.backup': JSON.stringify([
					{ id: 'k1', values: { name: 'Ali', phone: '+1 415 555 0103' } }
				]),
				'calls.busy': 'same',
				'calls.hours_same': 'yes',
				'calls.after_hours': 'emergency',
				'calls.emergency_phone': JSON.stringify([
					{ id: 'e1', values: { name: 'On-call', phone: '+1 415 555 0104' } }
				]),
				'calls.language': JSON.stringify({ same_as: 'business.language' }),
				'calls.voicemail_type': 'write',
				'calls.voicemail_words': 'Thanks for calling. Leave your name and number.',
				'calls.alert_people': JSON.stringify([
					{ id: 'n1', values: { name: 'Sam', email: 'sam@example.com' } }
				]),
				'calls.missed_text': 'yes',
				'calls.missed_text_words': 'Sorry we missed you — we will ring back within the hour.',
				'calls.test_person': JSON.stringify([
					{ id: 't1', values: { name: 'Sam', phone: '+1 415 555 0101', when: 'Weekday mornings' } }
				])
			};
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(JSON.parse(resumed['calls.port_account']!.value!)[0].values.postal_code).toBe('94607');
			expect(missingRequiredFacts(calls, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(calls))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});

		it('lets a client send the setup before they know who rings or who takes the test call', () => {
			const later = { availability: 'not_yet' as const, value: null, note: null };
			const answers: SetupAnswers = {
				'business.country': have('GB'),
				'business.language': have('English'),
				'calls.number_plan': have('new'),
				'calls.new_number_area': later,
				'calls.ring_people': later,
				'calls.ring_mode': have('together'),
				'calls.ring_time': have('20'),
				'calls.no_answer': have('voicemail'),
				'calls.busy': have('same'),
				'calls.hours_same': have('yes'),
				'calls.after_hours': have('voicemail'),
				'calls.language': have('{"same_as":"business.language"}'),
				'calls.voicemail_type': have('standard'),
				'calls.alert_people': have('[{"id":"n1","values":{"name":"Sam"}}]'),
				'calls.missed_text': have('no'),
				'calls.test_person': later
			};
			expect(missingRequiredFacts(calls, answers, shown(answers))).toEqual([]);
		});
	});

	describe('Texting registration', () => {
		const texting = starter.sections.find((section) => section.key === 'texting')!;
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);
		const later = { availability: 'not_yet' as const, value: null, note: null };

		it('is shown only to a package with Calls and texting, after the calls stage', () => {
			expect(texting.serviceKey).toBe('calls_texting');
			expect(stages.map((stage) => stage.key).indexOf('texting')).toBeGreaterThan(
				stages.map((stage) => stage.key).indexOf('calls')
			);
		});

		it('asks each follow-up only after its answer', () => {
			for (const [gate, value, followUps] of [
				['texting.details_match', 'no', ['texting.registered_details']],
				[
					'texting.has_registration_number',
					'yes',
					['texting.registration_number', 'texting.registration_document']
				],
				['texting.has_links', 'yes', ['texting.links']],
				['texting.has_opt_out_list', 'yes', ['texting.opt_out_list']]
			] as const) {
				const other = value === 'yes' ? 'no' : 'yes';
				for (const key of followUps) {
					expect(shown({ [gate]: have(value) }).has(key), key).toBe(true);
					expect(shown({ [gate]: have(other) }).has(key), key).toBe(false);
				}
			}
			expect(
				shown({ 'texting.has_registration_number': have('not_sure') }).has(
					'texting.registration_number'
				)
			).toBe(false);
		});

		it('keeps registration papers and opt-out lists protected, and never requires the papers', () => {
			expect(facts.get('texting.registration_document')).toMatchObject({
				kind: 'protected_file',
				required: false
			});
			expect(facts.get('texting.opt_out_list')!.kind).toBe('protected_file');
		});

		it('asks the monthly texts and consent ways the CRM texting registration uses', () => {
			expect(facts.get('texting.monthly_volume')!.options!.map((o) => o.value)).toEqual([
				'under_500',
				'500_2000',
				'2001_10000',
				'over_10000'
			]);
			const method = facts
				.get('texting.consent')!
				.listFields!.find((field) => field.key === 'method')!;
			for (const value of ['website_form', 'paper_form', 'verbal', 'text_initiated', 'other'])
				expect(method.options!.map((o) => o.value)).toContain(value);
		});

		it('lets a sole trader with no number and no samples yet still send the setup', () => {
			const answers: SetupAnswers = {
				'texting.details_match': have('yes'),
				'texting.has_registration_number': have('no'),
				'texting.website': later,
				'texting.representative': have(
					'[{"id":"r1","values":{"first_name":"Sam","last_name":"Raad","title":"Owner","position":"owner","email":"sam@example.com","phone":"+447700900123"}}]'
				),
				'texting.representative_agrees': have('yes'),
				'texting.message_kinds': have('["replies","appointments"]'),
				'texting.recipients': have('["customers"]'),
				'texting.monthly_volume': have('under_500'),
				'texting.quiet_hours': have('8_to_9'),
				'texting.has_links': have('no'),
				'texting.samples': later,
				'texting.consent': later,
				'texting.no_bought_lists': have('yes'),
				'texting.stop_help': have('yes'),
				'texting.privacy_url': later,
				'texting.terms_url': later,
				'texting.has_opt_out_list': have('no')
			};
			expect(missingRequiredFacts(texting, answers, shown(answers))).toEqual([]);
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const sent: Record<string, string> = {
				'texting.details_match': 'no',
				'texting.registered_details': JSON.stringify([
					{
						id: 'd1',
						values: {
							legal_name: 'Raad Plumbing LLC',
							line1: '12 Main St',
							city: 'Oakland',
							postal_code: '94607'
						}
					}
				]),
				'texting.has_registration_number': 'yes',
				'texting.registration_number': '12-3456789',
				'texting.registration_document': JSON.stringify(['00000000-0000-4000-8000-000000000002']),
				'texting.website': 'https://raadplumbing.example',
				'texting.representative': JSON.stringify([
					{
						id: 'r1',
						values: {
							first_name: 'Sam',
							last_name: 'Raad',
							title: 'Owner',
							position: 'owner',
							email: 'sam@raadplumbing.example',
							phone: '+1 415 555 0100'
						}
					}
				]),
				'texting.representative_agrees': 'yes',
				'texting.message_kinds': JSON.stringify(['replies', 'appointments', 'marketing']),
				'texting.recipients': JSON.stringify(['customers', 'Property managers we work with']),
				'texting.monthly_volume': '500_2000',
				'texting.quiet_hours': '8_to_9',
				'texting.has_links': 'yes',
				'texting.links': JSON.stringify([
					{ id: 'l1', values: { value: 'raadplumbing.example' } },
					{ id: 'l2', values: { value: '+1 415 555 0100' } }
				]),
				'texting.samples': JSON.stringify([
					{
						id: 's1',
						values: {
							message: 'Raad Plumbing: Hi Sam, Ali is on his way, about 2pm. Reply STOP to opt out.'
						}
					},
					{
						id: 's2',
						values: {
							message: 'Raad Plumbing: your quote is ready to view. Reply STOP to opt out.'
						}
					}
				]),
				'texting.consent': JSON.stringify([
					{
						id: 'c1',
						values: {
							method: 'website_form',
							purpose: 'both',
							wording: 'I agree to get texts about my job from Raad Plumbing. Reply STOP to stop.',
							link: 'https://raadplumbing.example/contact'
						}
					}
				]),
				'texting.no_bought_lists': 'yes',
				'texting.stop_help': 'yes',
				'texting.privacy_url': 'https://raadplumbing.example/privacy',
				'texting.terms_url': 'https://raadplumbing.example/texting-terms',
				'texting.has_opt_out_list': 'yes',
				'texting.opt_out_list': JSON.stringify(['00000000-0000-4000-8000-000000000003'])
			};
			const parsed = setupAnswersSchema(facts).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = {};
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(missingRequiredFacts(texting, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(texting))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});
	});

	describe('Review requests', () => {
		const reviews = starter.sections.find((section) => section.key === 'reviews')!;
		const forPackage = (...services: string[]) => {
			const catalogue = catalogueForServices(starter, new Set(services));
			return {
				facts: catalogueFacts(catalogue),
				section: catalogue.sections.find((section) => section.key === 'reviews')!
			};
		};
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);

		it('is shown only to a package with Review requests', () => {
			expect(reviews.serviceKey).toBe('reviews');
			expect(forPackage('website').section).toBeUndefined();
		});

		it('offers texting only to a package with Calls and texting', () => {
			expect(forPackage('reviews').facts.has('reviews.channel')).toBe(false);
			expect(forPackage('reviews', 'calls_texting').facts.has('reviews.channel')).toBe(true);
		});

		it('confirms the name and sending times from earlier stages, or asks them here', () => {
			const all = forPackage('reviews', 'google_profile', 'calls_texting').facts;
			expect(all.get('reviews.send_hours')!.reuseFrom).toBe('texting.quiet_hours');
			const alone = forPackage('reviews').facts;
			expect(alone.get('reviews.send_hours')!.reuseFrom).toBeUndefined();
			expect(alone.get('reviews.display_name')!.reuseFrom).toBe('business.public_name');
		});

		it('uses the CRM review settings’ own message styles', () => {
			const tones = facts.get('reviews.tone')!.options!.map((option) => option.value);
			for (const style of ['friendly', 'professional', 'short']) expect(tones).toContain(style);
		});

		it('never asks which customers to leave out, or offers a way to reward reviews', () => {
			const wording = sectionFacts(reviews)
				.flatMap((fact) => [fact.label, ...(fact.options ?? []).map((option) => option.label)])
				.join(' ')
				.toLowerCase();
			for (const word of ['happy customers only', 'unhappy', 'low rating only', 'discount for'])
				expect(wording).not.toContain(word);
			expect(facts.get('reviews.same_for_everyone')!.required).toBe(true);
			expect(facts.get('reviews.no_rewards')!.required).toBe(true);
		});

		it('asks for past customers, protected, only after a yes', () => {
			for (const key of ['reviews.past_customer_list', 'reviews.past_customers_real']) {
				expect(shown({ 'reviews.past_customers': have('yes') }).has(key), key).toBe(true);
				for (const other of ['no', 'not_sure'])
					expect(shown({ 'reviews.past_customers': have(other) }).has(key), key).toBe(false);
			}
			expect(facts.get('reviews.past_customer_list')).toMatchObject({
				kind: 'protected_file',
				canDefer: true
			});
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const earlier: SetupAnswers = {
				'business.public_name': have('Raad Plumbing'),
				'gbp.situation': have('own'),
				'gbp.link': have('https://maps.app.goo.gl/abc123'),
				'texting.quiet_hours': have('8_to_9')
			};
			const sent: Record<string, string> = {
				'reviews.google_link': 'https://maps.app.goo.gl/abc123',
				'reviews.display_name': JSON.stringify({ same_as: 'business.public_name' }),
				'reviews.feedback_people': JSON.stringify([
					{ id: 'f1', values: { name: 'Sam Raad', email: 'sam@raadplumbing.example' } }
				]),
				'reviews.channel': 'sms',
				'reviews.first_send': 'job_completed',
				'reviews.reminders': 'two',
				'reviews.send_hours': JSON.stringify({ same_as: 'texting.quiet_hours' }),
				'reviews.tone': 'friendly',
				'reviews.tone_note': 'Sign off from Sam.',
				'reviews.past_customers': 'yes',
				'reviews.past_customer_list': JSON.stringify(['00000000-0000-4000-8000-000000000004']),
				'reviews.past_customers_real': 'yes',
				'reviews.same_for_everyone': 'yes',
				'reviews.no_rewards': 'yes'
			};
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(missingRequiredFacts(reviews, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(reviews))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});

		it('lets a client without a Google profile yet still send the setup', () => {
			const { facts: own, section } = forPackage('reviews');
			const answers: SetupAnswers = {
				'business.public_name': have('Raad Plumbing'),
				'reviews.google_link': { availability: 'not_yet', value: null, note: null },
				'reviews.display_name': have('{"same_as":"business.public_name"}'),
				'reviews.feedback_people': have(
					'[{"id":"f1","values":{"name":"Sam","email":"sam@example.com"}}]'
				),
				'reviews.first_send': have('job_completed'),
				'reviews.reminders': have('two'),
				'reviews.send_hours': have('8_to_9'),
				'reviews.past_customers': have('no'),
				'reviews.same_for_everyone': have('yes'),
				'reviews.no_rewards': have('yes')
			};
			expect(own.has('reviews.channel')).toBe(false);
			expect(
				missingRequiredFacts(section, answers, shownFacts(sectionFacts(section), answers))
			).toEqual([]);
		});
	});

	describe('How your CRM should work', () => {
		const crm = starter.sections.find((section) => section.key === 'crm')!;
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);
		const forPackage = (...services: string[]) =>
			catalogueFacts(catalogueForServices(starter, new Set(services)));

		it('is shown to everyone, with the working hours built in', () => {
			expect(crm.serviceKey).toBeNull();
			expect(facts.get('crm.work_hours')).toMatchObject({ kind: 'hours', builtIn: true });
		});

		it('confirms enquiry recipients and payment methods from earlier stages, or asks them here', () => {
			const website = forPackage('website');
			expect(website.get('crm.enquiry_recipients')!.reuseFrom).toBe('website.form_recipients');
			expect(website.get('crm.payment_methods')!.reuseFrom).toBe('proof.payment_methods');
			const alone = forPackage();
			expect(alone.get('crm.enquiry_recipients')!.reuseFrom).toBeUndefined();
			expect(alone.get('crm.enquiry_recipients')!.kind).toBe('list');
		});

		it('never books work for the client and assumes no tax', () => {
			const path = facts.get('crm.enquiry_path')!;
			expect(path.options!.find((option) => option.label.includes('recommended'))!.value).toBe(
				'review'
			);
			expect(facts.get('crm.tax')!.options!.map((option) => option.value)).not.toContain(
				'recommended'
			);
			expect(facts.get('crm.tax')!.canDefer).toBe(true);
		});

		it('asks the deposit rule only when a deposit is taken, and its amount by how it is worked out', () => {
			const never = shown({ 'crm.deposit': have('never') });
			for (const key of ['crm.deposit_type', 'crm.deposit_percentage', 'crm.deposit_note'])
				expect(never.has(key), key).toBe(false);
			const some = shown({
				'crm.deposit': have('some'),
				'crm.deposit_type': have('percentage')
			});
			expect(some.has('crm.deposit_percentage')).toBe(true);
			expect(some.has('crm.deposit_amount')).toBe(false);
			expect(some.has('crm.deposit_note')).toBe(true);
			expect(shown({ 'crm.deposit': have('always') }).has('crm.deposit_note')).toBe(false);
		});

		it('asks tax numbers only when tax is charged', () => {
			expect(shown({ 'crm.tax': have('not_registered') }).has('crm.tax_numbers')).toBe(false);
			expect(shown({ 'crm.tax': have('added') }).has('crm.tax_numbers')).toBe(true);
		});

		it('offers the website quick reply only to a package with a website', () => {
			expect(forPackage().has('crm.quick_reply')).toBe(false);
			expect(forPackage('website').has('crm.quick_reply')).toBe(true);
		});

		it('accepts a weekly timetable for the working hours', () => {
			const week = JSON.stringify({
				mode: 'weekly',
				days: [0, 1, 2, 3, 4, 5, 6].map((day) => ({
					open: day > 0 && day < 6,
					all_day: false,
					periods: day > 0 && day < 6 ? [['08:00', '17:00']] : []
				}))
			});
			expect(
				setupAnswerShortfall(facts.get('crm.work_hours')!, { 'crm.work_hours': have(week) })
			).toBeNull();
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const earlier: SetupAnswers = {
				'proof.payment_methods': have('["card","bank_transfer"]')
			};
			const sent: Record<string, string> = {
				'crm.enquiry_path': 'review',
				'crm.assessment_when': 'Anything bigger than one room.',
				'crm.enquiry_recipients': JSON.stringify([
					{ id: 'r1', values: { name: 'Sam Raad', email: 'sam@raadplumbing.example' } }
				]),
				'crm.enquiry_owner': 'someone_else',
				'crm.enquiry_owner_person': JSON.stringify([{ id: 'o1', values: { name: 'Ali' } }]),
				'crm.quote_needs': JSON.stringify(['address', 'photos']),
				'crm.reply_target': '1_hour',
				'crm.teams': 'separate',
				'crm.team_units': JSON.stringify([
					{ id: 't1', values: { name: 'Heating', handles: 'Boilers' } }
				]),
				'crm.quote_valid_days': '30',
				'crm.quote_approval': 'yes',
				'crm.deposit': 'some',
				'crm.deposit_type': 'fixed',
				'crm.deposit_amount': JSON.stringify({ amount: '250', currency: 'GBP' }),
				'crm.deposit_note': 'Jobs where materials are ordered.',
				'crm.quote_terms': 'Prices include labour and materials.',
				'crm.work_hours': JSON.stringify({ mode: 'appointment_only' }),
				'crm.notice': 'next_day',
				'crm.travel_buffer': JSON.stringify({ amount: 30, unit: 'minutes' }),
				'crm.visit_types': JSON.stringify([
					{
						id: 'v1',
						values: {
							name: 'Estimate visit',
							length: '1 hour',
							arrival: '2_hours',
							purpose: 'assessment'
						}
					}
				]),
				'crm.pricing': 'mix',
				'crm.price_list': 'yes',
				'crm.invoice_due': 'days',
				'crm.invoice_due_days': '14',
				'crm.tax': 'added',
				'crm.tax_numbers': JSON.stringify([
					{ id: 'x1', values: { name: 'VAT', number: 'GB123456789' } }
				]),
				'crm.payment_methods': JSON.stringify({ same_as: 'proof.payment_methods' }),
				'crm.payment_instructions': 'Bank transfer to the account on the invoice.',
				'crm.team_members': JSON.stringify([
					{ id: 'm1', values: { name: 'Ali', email: 'ali@raadplumbing.example', role: 'field' } }
				]),
				'crm.alert_people': JSON.stringify(['m1']),
				'crm.quote_followups': 'yes',
				'crm.message_approver': 'final_approver'
			};
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(missingRequiredFacts(crm, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(crm))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});
	});

	describe('Move your existing data', () => {
		const imports = starter.sections.find((section) => section.key === 'import')!;
		const shownHere = (answers: SetupAnswers) => shownFacts(sectionFacts(imports), answers);

		it('is shown to everyone, and starting fresh asks nothing more', () => {
			expect(imports.serviceKey).toBeNull();
			const fresh: SetupAnswers = { 'import.wanted': have('no') };
			expect([...shownHere(fresh)]).toEqual(['import.wanted']);
			expect(missingRequiredFacts(imports, fresh, shownHere(fresh))).toEqual([]);
		});

		it('keeps the files protected and lets them wait', () => {
			expect(facts.get('import.files')).toMatchObject({ kind: 'protected_file', canDefer: true });
		});

		it('asks who approves the preview, and to confirm nothing is sent, before anything comes in', () => {
			const yes = shownHere({ 'import.wanted': have('yes') });
			for (const key of [
				'import.source',
				'import.what',
				'import.files',
				'import.approver',
				'import.nothing_sent'
			])
				expect(yes.has(key), key).toBe(true);
			expect(yes.has('import.approver_person')).toBe(false);
			expect(
				shownHere({ 'import.wanted': have('yes'), 'import.approver': have('someone_else') }).has(
					'import.approver_person'
				)
			).toBe(true);
			expect(facts.get('import.nothing_sent')!.required).toBe(true);
		});
	});
	describe('Marketing campaigns', () => {
		const marketing = starter.sections.find((section) => section.key === 'marketing')!;
		const forPackage = (...services: string[]) => {
			const catalogue = catalogueForServices(starter, new Set(services));
			return {
				facts: catalogueFacts(catalogue),
				section: catalogue.sections.find((section) => section.key === 'marketing')!
			};
		};
		const shown = (answers: SetupAnswers) => shownCatalogueFacts(starter, answers);

		it('is shown only to a package with Marketing campaigns', () => {
			expect(marketing.serviceKey).toBe('marketing');
			expect(forPackage('website').section).toBeUndefined();
		});

		it('offers texts only to a package with Calls and texting, and asks text permission only for texts', () => {
			expect(forPackage('marketing').facts.has('marketing.channel')).toBe(false);
			expect(forPackage('marketing').facts.has('marketing.text_permission')).toBe(false);
			const texting = forPackage('marketing', 'calls_texting').facts;
			expect(texting.has('marketing.channel')).toBe(true);
			const withTexting = catalogueForServices(starter, new Set(['marketing', 'calls_texting']));
			const asked = (channel: string) =>
				shownCatalogueFacts(withTexting, { 'marketing.channel': have(channel) }).has(
					'marketing.text_permission'
				);
			expect(asked('email')).toBe(false);
			for (const channel of ['text', 'both']) expect(asked(channel), channel).toBe(true);
		});

		it('picks services and places from Services and service area, and confirms earlier facts', () => {
			expect(facts.get('marketing.services')).toMatchObject({
				kind: 'pick',
				pickFrom: 'services.offered',
				required: true
			});
			expect(facts.get('marketing.places')).toMatchObject({
				kind: 'pick',
				pickFrom: 'area.places'
			});
			expect(facts.get('marketing.places')!.required).toBe(false);
			const website = forPackage('marketing', 'website').facts;
			expect(website.get('marketing.sender_name')!.reuseFrom).toBe('business.public_name');
			expect(website.get('marketing.reply_people')!.reuseFrom).toBe('website.form_recipients');
			const alone = forPackage('marketing').facts;
			expect(alone.get('marketing.reply_people')!.reuseFrom).toBeUndefined();
			expect(alone.get('marketing.reply_people')!.kind).toBe('list');
		});

		it('never asks about paid advertising, and keeps contact lists protected', () => {
			const wording = sectionFacts(marketing)
				.flatMap((fact) => [
					fact.label,
					fact.hint ?? '',
					...(fact.options ?? []).map((o) => o.label)
				])
				.join(' ')
				.toLowerCase();
			for (const word of ['ad account', 'ad budget', 'facebook ads', 'google ads', 'pixel'])
				expect(wording).not.toContain(word);
			for (const key of ['marketing.list', 'marketing.opt_out_list', 'marketing.permission_proof'])
				expect(facts.get(key)!.kind, key).toBe('protected_file');
		});

		it('asks each follow-up only after the answer that needs it', () => {
			const rules: [string, string, string, string][] = [
				['marketing.list', 'marketing.sources', '["upload"]', '["crm"]'],
				['marketing.opt_out_list', 'marketing.has_opt_out_list', 'yes', 'no'],
				['marketing.offer', 'marketing.has_offer', 'yes', 'no'],
				['marketing.action_link', 'marketing.action', 'website_page', 'request']
			];
			for (const [key, source, on, off] of rules) {
				expect(shown({ [source]: have(on) }).has(key), key).toBe(true);
				expect(shown({ [source]: have(off) }).has(key), key).toBe(false);
			}
		});

		it('only ever makes a draft', () => {
			expect(facts.get('marketing.draft_only')).toMatchObject({ kind: 'choice', required: true });
		});

		it('saves a full answer and shows it again when the client comes back', () => {
			const earlier: SetupAnswers = {
				'business.public_name': have('Raad Plumbing'),
				'services.offered': have(
					'[{"id":"s1","values":{"name":"Boiler service","season":"all_year"}}]'
				),
				'area.places': have('[{"id":"a1","values":{"name":"Leeds"}}]'),
				'website.form_recipients': have(
					'[{"id":"r1","values":{"name":"Sam Raad","email":"sam@raadplumbing.example"}}]'
				)
			};
			const sent: Record<string, string> = {
				'marketing.goal': 'repeat_work',
				'marketing.services': JSON.stringify(['s1']),
				'marketing.places': JSON.stringify(['a1']),
				'marketing.audience': 'past_customers',
				'marketing.audience_note': 'Everyone with a boiler service over a year ago.',
				'marketing.exclusions': JSON.stringify(['complaint', 'booked']),
				'marketing.sources': JSON.stringify(['crm', 'upload']),
				'marketing.list': JSON.stringify(['00000000-0000-4000-8000-000000000005']),
				'marketing.email_permission': 'customer_could_refuse',
				'marketing.permission_story': 'Our quote form says we send a few offers a year.',
				'marketing.has_opt_out_list': 'yes',
				'marketing.opt_out_list': JSON.stringify(['00000000-0000-4000-8000-000000000006']),
				'marketing.has_offer': 'yes',
				'marketing.offer': '10% off a boiler service booked before 31 March, one per home.',
				'marketing.capacity': '20',
				'marketing.channel': 'both',
				'marketing.text_permission': 'said_yes_texts',
				'marketing.start_date': '2027-02-01',
				'marketing.follow_up': 'one',
				'marketing.sender_name': JSON.stringify({ same_as: 'business.public_name' }),
				'marketing.reply_people': JSON.stringify({ same_as: 'website.form_recipients' }),
				'marketing.action': 'request',
				'marketing.tone': 'friendly',
				'marketing.draft_only': 'yes'
			};
			const parsed = setupAnswersSchema(facts, earlier).safeParse({
				answers: Object.entries(sent).map(([fact_key, value]) => ({
					fact_key,
					availability: 'have',
					value,
					note: null
				}))
			});
			expect(parsed.error?.issues ?? []).toEqual([]);

			const resumed: SetupAnswers = { ...earlier };
			for (const answer of parsed.data!.answers) {
				const stored = answer.value;
				resumed[answer.fact_key] = have(
					typeof stored === 'string' ? stored : JSON.stringify(stored)
				);
			}
			expect(missingRequiredFacts(marketing, resumed, shown(resumed))).toEqual([]);
			for (const fact of sectionFacts(marketing))
				expect(setupAnswerShortfall(fact, resumed), fact.key).toBeNull();
		});

		it('lets a client without their permission facts yet still send the setup', () => {
			const { facts: own, section } = forPackage('marketing');
			const later = { availability: 'not_yet' as const, value: null, note: null };
			const answers: SetupAnswers = {
				'business.public_name': have('Raad Plumbing'),
				'services.offered': have('[{"id":"s1","values":{"name":"Boiler service"}}]'),
				'marketing.goal': have('referrals'),
				'marketing.services': have('["s1"]'),
				'marketing.audience': have('past_customers'),
				'marketing.exclusions': have('["nobody_else"]'),
				'marketing.sources': have('["crm"]'),
				'marketing.email_permission': later,
				'marketing.permission_story': later,
				'marketing.has_opt_out_list': have('no'),
				'marketing.has_offer': have('no'),
				'marketing.capacity': have('10'),
				'marketing.start_date': later,
				'marketing.follow_up': have('none'),
				'marketing.sender_name': have('{"same_as":"business.public_name"}'),
				'marketing.reply_people': have(
					'[{"id":"r1","values":{"name":"Sam","email":"sam@example.com"}}]'
				),
				'marketing.action': have('call'),
				'marketing.draft_only': have('yes')
			};
			expect(own.has('marketing.channel')).toBe(false);
			expect(
				missingRequiredFacts(section, answers, shownFacts(sectionFacts(section), answers))
			).toEqual([]);
		});
	});
});
