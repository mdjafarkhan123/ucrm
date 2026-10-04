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
import { missingRequiredFacts, setupAnswerShortfall } from './catalogue';

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
		expect(stages.map((stage) => stage.key)).toEqual(['business', 'services', 'brand']);
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
});
