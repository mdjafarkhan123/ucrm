import { describe, expect, it } from 'vitest';
import { SETUP_CATALOGUE_1, SETUP_VERSION_1 } from './catalogue.fixture';
import {
	BUILT_IN_FACTS,
	buildSetupCatalogue,
	catalogueFacts,
	catalogueForServices,
	missingRequiredFacts,
	sectionFacts,
	sectionStatus,
	setupValueError,
	shownFacts,
	type SetupAnswers,
	type SetupFact
} from './catalogue';

const SETUP_SECTIONS = SETUP_CATALOGUE_1.sections;
const SETUP_FACTS = catalogueFacts(SETUP_CATALOGUE_1);
const business = SETUP_SECTIONS.find((section) => section.key === 'business')!;
const have = (value: string) => ({ availability: 'have' as const, value, note: null });

function allRequiredAnswered(): SetupAnswers {
	return Object.fromEntries(
		sectionFacts(business)
			.filter((fact) => fact.required)
			.map((fact) => [fact.key, have('x')])
	);
}

describe('setup catalogue', () => {
	it('asks each fact once across every section', () => {
		const keys = SETUP_SECTIONS.flatMap((section) => sectionFacts(section).map((fact) => fact.key));
		expect(new Set(keys).size).toBe(keys.length);
		expect(SETUP_FACTS.size).toBe(keys.length);
	});

	it('uses keys the database accepts', () => {
		for (const key of SETUP_FACTS.keys())
			expect(key).toMatch(/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/);
	});

	it('knows the answer rules of every built-in question', () => {
		for (const fact of SETUP_FACTS.values())
			if (fact.builtIn) expect(BUILT_IN_FACTS[fact.key]).toBeDefined();
	});

	it('groups questions under the heading before them, as the old cards did', () => {
		expect(business.groups.map((group) => group.title)).toEqual([
			'Business identity',
			'Who Uplift talks to',
			'How customers reach you',
			'Where you’re based',
			'Language, time and money',
			'Opening hours'
		]);
		expect(business.groups[0].facts.map((fact) => fact.key)).toEqual([
			'business.public_name',
			'business.legal_name',
			'business.trade',
			'business.type'
		]);
	});

	it('takes a built-in question’s answer type from the app, never the database', () => {
		const tampered = structuredClone(SETUP_VERSION_1);
		const currency = tampered.stages[0].items.find(
			(item) => item.fact_key === 'business.currency'
		)!;
		currency.kind = 'text';
		const fact = catalogueFacts(buildSetupCatalogue(tampered)).get('business.currency')!;
		expect(fact.kind).toBe('choice');
		expect(fact.options?.some((option) => option.value === 'GBP')).toBe(true);
	});

	it('leaves out a built-in question the app has no rules for', () => {
		const ahead = structuredClone(SETUP_VERSION_1);
		ahead.stages[0].items.push({ ...ahead.stages[0].items[1], fact_key: 'business.unknown' });
		const facts = catalogueFacts(buildSetupCatalogue(ahead));
		expect(facts.has('business.unknown')).toBe(false);
		expect(facts.size).toBe(SETUP_FACTS.size);
	});

	it('uses a custom question’s own answer type', () => {
		expect(SETUP_FACTS.get('business.hours_seasonal')).toMatchObject({
			kind: 'longtext',
			maxLength: 500,
			builtIn: false
		});
	});

	it('asks yes/no as two radio choices and a date as a date', () => {
		const custom = buildSetupCatalogue({
			version_id: 'v',
			stages: [
				{
					key: 'extra',
					title: 'Extra',
					description: '',
					service_key: null,
					items: (['yes_no', 'date'] as const).map((kind) => ({
						type: 'question' as const,
						fact_key: `extra.${kind}`,
						label: kind,
						hint: null,
						built_in: false,
						required: false,
						can_defer: false,
						kind,
						options: null,
						max_length: null
					}))
				}
			]
		});
		const facts = catalogueFacts(custom);
		const yesNo = facts.get('extra.yes_no')!;
		expect(yesNo).toMatchObject({ kind: 'choice', layout: 'radio' });
		expect(setupValueError(yesNo, 'yes')).toBeNull();
		expect(setupValueError(yesNo, 'maybe')).not.toBeNull();
		const date = facts.get('extra.date')!;
		expect(date.kind).toBe('date');
		expect(setupValueError(date, '2026-02-28')).toBeNull();
		expect(setupValueError(date, '2026-02-30')).not.toBeNull();
		expect(setupValueError(date, '28/02/2026')).not.toBeNull();
	});

	it('never asks for a password or provider credential', () => {
		for (const fact of SETUP_FACTS.values())
			expect(`${fact.key} ${fact.label}`.toLowerCase()).not.toMatch(/password|secret|token/);
	});
});

describe('setupValueError', () => {
	const email = SETUP_FACTS.get('business.contact_email')!;
	const phone = SETUP_FACTS.get('business.public_phone')!;
	const type = SETUP_FACTS.get('business.type')!;
	const name = SETUP_FACTS.get('business.public_name')!;

	it('accepts an empty value, because clearing an answer is allowed', () => {
		expect(setupValueError(email, '  ')).toBeNull();
	});

	it('refuses a half-typed email and accepts a whole one', () => {
		expect(setupValueError(email, 'sam@')).not.toBeNull();
		expect(setupValueError(email, 'sam@brightspark.co.uk')).toBeNull();
	});

	it('accepts phone numbers as people write them and refuses words', () => {
		expect(setupValueError(phone, '+44 20 7946 0958')).toBeNull();
		expect(setupValueError(phone, '(555) 010-2299')).toBeNull();
		expect(setupValueError(phone, 'call me')).not.toBeNull();
		expect(setupValueError(phone, '12345')).not.toBeNull();
	});

	it('only accepts a listed choice', () => {
		expect(setupValueError(type, 'company')).toBeNull();
		expect(setupValueError(type, 'charity')).not.toBeNull();
	});

	it('accepts a real country code and time zone and refuses made-up ones', () => {
		const country = SETUP_FACTS.get('business.country')!;
		const timezone = SETUP_FACTS.get('business.timezone')!;
		expect(setupValueError(country, 'GB')).toBeNull();
		expect(setupValueError(country, 'United Kingdom')).not.toBeNull();
		expect(setupValueError(timezone, 'Europe/London')).toBeNull();
		expect(setupValueError(timezone, 'Mars/Olympus')).not.toBeNull();
	});

	it('holds text to its length', () => {
		expect(setupValueError(name, 'a'.repeat(120))).toBeNull();
		expect(setupValueError(name, 'a'.repeat(121))).not.toBeNull();
	});
});

describe('section status', () => {
	// No question in these tests has a rule, so every one is asked.
	const everyQuestion = new Set(sectionFacts(business).map((fact) => fact.key));

	it('is not started until something is answered', () => {
		expect(sectionStatus(business, {}, false, everyQuestion)).toBe('not_started');
	});

	it('is in progress once anything is answered', () => {
		expect(
			sectionStatus(
				business,
				{ 'business.public_name': have('Bright Spark') },
				false,
				everyQuestion
			)
		).toBe('in_progress');
	});

	it('is done only when marked done and every required fact has an answer', () => {
		const answers = allRequiredAnswered();
		expect(sectionStatus(business, answers, false, everyQuestion)).toBe('in_progress');
		expect(sectionStatus(business, answers, true, everyQuestion)).toBe('done');
	});

	it('reopens by itself when a required answer is cleared after being marked done', () => {
		const answers = allRequiredAnswered();
		delete answers['business.contact_name'];
		expect(sectionStatus(business, answers, true, everyQuestion)).toBe('in_progress');
		expect(missingRequiredFacts(business, answers, everyQuestion).map((fact) => fact.key)).toEqual([
			'business.contact_name'
		]);
	});

	it('counts "need help" and "not yet" as answers, without a value', () => {
		const answers = allRequiredAnswered();
		answers['business.public_phone'] = { availability: 'need_help', value: null, note: null };
		answers['business.public_email'] = { availability: 'not_yet', value: null, note: 'Soon' };
		expect(missingRequiredFacts(business, answers, everyQuestion)).toEqual([]);
		expect(sectionStatus(business, answers, true, everyQuestion)).toBe('done');
	});
});

describe('stages each client sees (A4)', () => {
	const websiteQuestion = {
		type: 'question' as const,
		fact_key: 'website.domain',
		label: 'Your domain',
		hint: null,
		built_in: false,
		required: true,
		can_defer: true,
		kind: 'text' as const,
		options: null,
		max_length: 200
	};
	const version = {
		...SETUP_VERSION_1,
		stages: [
			...SETUP_VERSION_1.stages,
			{
				key: 'website',
				title: 'Website',
				description: '',
				service_key: 'website',
				items: [websiteQuestion]
			},
			{ key: 'marketing', title: 'Marketing', description: '', service_key: 'marketing', items: [] }
		]
	};

	it('leaves out a stage that has no questions yet', () => {
		const keys = buildSetupCatalogue(version).sections.map((section) => section.key);
		expect(keys).toEqual(['business', 'website']);
	});

	it('shows a service stage only to a package that includes the service', () => {
		const catalogue = buildSetupCatalogue(version);
		const keys = (services: string[]) =>
			catalogueForServices(catalogue, new Set(services)).sections.map((section) => section.key);
		expect(keys([])).toEqual(['business']);
		expect(keys(['reviews'])).toEqual(['business']);
		expect(keys(['website', 'reviews'])).toEqual(['business', 'website']);
	});
});

describe('show-only-if rules (A5b)', () => {
	const fact = (key: string, showIf?: SetupFact['showIf']): SetupFact => ({
		key,
		label: key,
		kind: 'choice',
		required: true,
		builtIn: false,
		...(showIf ? { showIf } : {})
	});
	const facts = [
		fact('website.has_site'),
		fact('website.domain', [{ factKey: 'website.has_site', values: ['yes'] }]),
		fact('website.host', [{ factKey: 'website.domain', values: ['own'] }])
	];

	it('asks a question only once an earlier answer matches, and hides its dependants with it', () => {
		expect([...shownFacts(facts, {})]).toEqual(['website.has_site']);
		const answers: SetupAnswers = {
			'website.has_site': have('yes'),
			'website.domain': have('own')
		};
		expect([...shownFacts(facts, answers)]).toEqual([
			'website.has_site',
			'website.domain',
			'website.host'
		]);
		answers['website.has_site'] = have('no');
		expect([...shownFacts(facts, answers)]).toEqual(['website.has_site']);
	});

	it('treats "need help" and "not yet" as no match', () => {
		const answers: SetupAnswers = {
			'website.has_site': { availability: 'need_help', value: null, note: null }
		};
		expect(shownFacts(facts, answers).has('website.domain')).toBe(false);
	});

	it('judges a rule on an earlier section from the questions known to be asked', () => {
		const later = [fact('website.domain', [{ factKey: 'business.type', values: ['company'] }])];
		const answers = { 'business.type': have('company') };
		expect(shownFacts(later, answers).has('website.domain')).toBe(false);
		expect(shownFacts(later, answers, new Set(['business.type'])).has('website.domain')).toBe(true);
	});

	it('settles service rules per package and never counts a hidden required question', () => {
		const version = {
			...SETUP_VERSION_1,
			stages: [
				{
					key: 'extras',
					title: 'Extras',
					description: '',
					service_key: null,
					items: [
						{
							type: 'question' as const,
							fact_key: 'extras.reviews_link',
							label: 'Review link',
							hint: null,
							built_in: false,
							required: true,
							can_defer: false,
							kind: 'yes_no' as const,
							options: null,
							max_length: null,
							show_if: [
								{ service_key: 'reviews' },
								{ fact_key: 'business.type', values: ['company'] }
							]
						}
					]
				}
			]
		};
		const catalogue = buildSetupCatalogue(version);
		expect(catalogueForServices(catalogue, new Set()).sections).toEqual([]);
		const [extras] = catalogueForServices(catalogue, new Set(['reviews'])).sections;
		expect(sectionFacts(extras)[0].showIf).toEqual([
			{ factKey: 'business.type', values: ['company'] }
		]);
		const shown = shownFacts(sectionFacts(extras), {});
		expect(missingRequiredFacts(extras, {}, shown)).toEqual([]);
		expect(sectionStatus(extras, {}, true, shown)).toBe('done');
	});
});
