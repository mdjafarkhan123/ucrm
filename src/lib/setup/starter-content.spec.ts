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
import { setupAnswersSchema } from '../server/validation/setup.schema';
import { missingRequiredFacts, setupAnswerShortfall, shownCatalogueFacts } from './catalogue';

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
			'google'
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

	it('only shows a question for answers its earlier question can give', () => {
		for (const fact of facts.values())
			for (const condition of fact.showIf ?? []) {
				if (!('values' in condition)) continue;
				const source = facts.get(condition.factKey);
				expect(source, `${fact.key} depends on ${condition.factKey}`).toBeDefined();
				const choices = source!.options?.map((option) => option.value) ?? [];
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
});
