import { describe, expect, it } from 'vitest';
import {
	buildSetupCatalogue,
	catalogueFacts,
	catalogueForServices,
	earlierAnswersFor,
	missingRequiredFacts,
	sectionStatus,
	setupAnswerGiven,
	setupValueError,
	shownCatalogueFacts,
	storedSetupValue,
	type SetupAnswers,
	type SetupCatalogueRow
} from './catalogue';
import { setupAnswerLines } from './answer-lines';
import { setupReuseSource, setupReuseValue } from './reuse';

type ItemRow = SetupCatalogueRow['stages'][number]['items'][number];

const item = (fields: Record<string, unknown>): ItemRow => ({
	type: 'question' as const,
	hint: null,
	built_in: false,
	required: true,
	can_defer: false,
	options: null,
	max_length: null,
	...(fields as Pick<ItemRow, 'fact_key' | 'label' | 'kind'>)
});

// The public phone in "Your business", then "Which phone should the website show?" in a Website stage that
// only clients with Website get, and a call-forwarding phone in a stage tied to Calls.
const version: SetupCatalogueRow = {
	version_id: 'v',
	stages: [
		{
			key: 'business',
			title: 'Your business',
			description: '',
			service_key: null,
			items: [
				item({
					fact_key: 'business.public_phone',
					label: 'Public phone',
					built_in: true,
					kind: null
				}),
				item({
					fact_key: 'business.areas',
					label: 'Where do you work?',
					kind: 'list',
					list_fields: [
						{ key: 'town', label: 'Town', kind: 'text', required: true },
						{
							key: 'how_far',
							label: 'How far',
							kind: 'choice',
							required: false,
							options: [{ value: 'near', label: 'Nearby only' }]
						}
					],
					max_rows: 10
				})
			]
		},
		{
			key: 'website',
			title: 'Website',
			description: '',
			service_key: 'website',
			items: [
				item({
					fact_key: 'website.phone',
					label: 'Which phone should the website show?',
					kind: 'reuse',
					reuse_from: 'business.public_phone'
				}),
				item({
					fact_key: 'website.areas',
					label: 'Which areas should the website name?',
					kind: 'reuse',
					reuse_from: 'business.areas',
					required: false
				})
			]
		},
		{
			key: 'calls',
			title: 'Calls',
			description: '',
			service_key: null,
			items: [
				item({
					fact_key: 'calls.forward_to',
					label: 'Which number should calls ring?',
					kind: 'reuse',
					reuse_from: 'website.phone'
				})
			]
		}
	]
};

const catalogue = buildSetupCatalogue(version);
const facts = catalogueFacts(catalogue);
const reuse = facts.get('website.phone')!;
const same = setupReuseValue('business.public_phone');
const have = (value: string) => ({ availability: 'have' as const, value, note: null });

describe('a reuse question in the catalogue', () => {
	it("takes the earlier question's answer rules, wording and section", () => {
		expect(reuse).toMatchObject({
			kind: 'phone',
			builtIn: false,
			required: true,
			reuseFrom: 'business.public_phone',
			reuseLabel: 'Public phone',
			reuseSection: { key: 'business', title: 'Your business' }
		});
	});

	it('is left out when it reuses another reuse', () => {
		expect(facts.has('calls.forward_to')).toBe(false);
	});

	it('is asked as a plain question of that type when the client is not asked the earlier one', () => {
		const sections: SetupCatalogueRow['stages'] = [
			{ ...version.stages[0], service_key: 'google' },
			version.stages[1]
		];
		const client = catalogueForServices(
			buildSetupCatalogue({ version_id: 'v', stages: sections }),
			new Set(['website'])
		);
		const plain = catalogueFacts(client).get('website.phone')!;
		expect(plain.kind).toBe('phone');
		expect(plain.reuseFrom).toBeUndefined();
	});

	it('brings the earlier answer along to the later section', () => {
		const answers: SetupAnswers = { 'business.public_phone': have('01632 960123') };
		expect(earlierAnswersFor(catalogue.sections[1], catalogue, answers)).toEqual(answers);
	});
});

describe('"Yes, use this"', () => {
	it('is stored once, as the earlier question it means', () => {
		expect(setupReuseSource(same)).toBe('business.public_phone');
		expect(storedSetupValue(reuse, same)).toEqual({ same_as: 'business.public_phone' });
	});

	it('is accepted only while the earlier answer is given', () => {
		const given: SetupAnswers = { 'business.public_phone': have('01632 960123') };
		expect(setupValueError(reuse, same, given)).toBeNull();
		expect(setupValueError(reuse, same, {})).toBe(
			'Answer “Public phone” first, or use a different one here.'
		);
		expect(
			setupValueError(reuse, same, {
				'business.public_phone': { availability: 'not_yet', value: null, note: null }
			})
		).not.toBeNull();
	});

	it('cannot name another question', () => {
		const given: SetupAnswers = { 'business.public_email': have('a@b.co') };
		expect(setupValueError(reuse, setupReuseValue('business.public_email'), given)).toBe(
			'This answer could not be read. Reload the page and try again.'
		);
	});

	it('counts as an answer only while the earlier answer is given', () => {
		const confirmed: SetupAnswers = { 'website.phone': have(same) };
		expect(setupAnswerGiven(reuse, confirmed)).toBe(false);
		const both = { ...confirmed, 'business.public_phone': have('01632 960123') };
		expect(setupAnswerGiven(reuse, both)).toBe(true);
		const website = catalogue.sections[1];
		const shown = shownCatalogueFacts(catalogue, both);
		expect(missingRequiredFacts(website, confirmed, shown).map((fact) => fact.key)).toEqual([
			'website.phone'
		]);
		expect(missingRequiredFacts(website, both, shown)).toEqual([]);
		expect(sectionStatus(website, both, true, shown)).toBe('done');
	});
});

describe('"Use a different one here"', () => {
	it("is kept for this question only, checked with the earlier question's rules", () => {
		expect(setupValueError(reuse, '01632 960999')).toBeNull();
		expect(storedSetupValue(reuse, '01632 960999')).toBe('01632 960999');
		expect(setupValueError(reuse, 'call me')).toBe('Enter a phone number with at least 7 digits.');
		expect(setupAnswerGiven(reuse, { 'website.phone': have('01632 960999') })).toBe(true);
	});

	it('of an add-another list is a list of its own', () => {
		const areas = facts.get('website.areas')!;
		const rows = JSON.stringify([{ id: 'a1', values: { town: 'Leeds' } }]);
		expect(areas.kind).toBe('list');
		expect(setupValueError(areas, rows)).toBeNull();
	});
});

describe('an earlier answer in words', () => {
	it('reads a list row by row, choices by their words', () => {
		const areas = facts.get('website.areas')!;
		const rows = JSON.stringify([
			{ id: 'a1', values: { town: 'Leeds', how_far: 'near' } },
			{ id: 'a2', values: { town: 'York' } }
		]);
		expect(setupAnswerLines(areas, rows)).toEqual(['Leeds · Nearby only', 'York']);
	});

	it('reads hours day by day', () => {
		const hours = {
			kind: 'hours' as const,
			key: 'h',
			label: 'Hours',
			required: true,
			builtIn: true
		};
		const closed = { open: false, all_day: false, periods: [] };
		const week = {
			mode: 'weekly',
			days: [
				closed,
				{ open: true, all_day: false, periods: [['08:00', '17:00']] },
				{ open: true, all_day: true, periods: [] },
				closed,
				closed,
				closed,
				closed
			]
		};
		expect(setupAnswerLines(hours, JSON.stringify(week)).slice(0, 3)).toEqual([
			'Sunday: Closed',
			'Monday: 08:00–17:00',
			'Tuesday: Open 24 hours'
		]);
	});

	it('reads a phone as it was typed', () => {
		expect(setupAnswerLines(reuse, '01632 960123')).toEqual(['01632 960123']);
	});
});
