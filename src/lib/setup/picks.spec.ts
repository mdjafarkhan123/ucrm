import { describe, expect, it } from 'vitest';
import {
	buildSetupCatalogue,
	catalogueFacts,
	setupAnswerShortfall,
	setupValueError,
	shownCatalogueFacts,
	storedSetupValue,
	type SetupAnswers,
	type SetupCatalogueRow
} from './catalogue';
import { onboardingCatalogue } from './onboarding-list';
import { keptSetupPickIds, parseSetupPick, setupPickInstruction, setupPickRowName } from './picks';

const item = (fields: Record<string, unknown>) => ({
	type: 'question' as const,
	hint: null,
	built_in: false,
	required: true,
	can_defer: false,
	options: null,
	max_length: null,
	...fields
});

// "Add every other service you offer", then "Which 3–5 services should Uplift promote first?" in a later
// stage, read through the catalogue as the page and the server read it.
const version: SetupCatalogueRow = {
	version_id: 'v',
	stages: [
		{
			key: 'services',
			title: 'Services',
			description: '',
			service_key: null,
			items: [
				item({
					fact_key: 'services.offered',
					label: 'Add every service you offer',
					kind: 'list',
					list_fields: [
						{ key: 'name', label: 'Service name', kind: 'text', required: true },
						{ key: 'note', label: 'Short note', kind: 'longtext', required: false }
					],
					max_rows: 20
				})
			]
		},
		{
			key: 'website',
			title: 'Website',
			description: '',
			service_key: null,
			items: [
				item({
					fact_key: 'website.promote',
					label: 'Which services should Uplift promote first?',
					kind: 'pick',
					pick_from: 'services.offered',
					min_choices: 3,
					max_choices: 5,
					ordered: true
				})
			]
		}
	]
};

const catalogue = buildSetupCatalogue(version);
const pick = catalogueFacts(catalogue).get('website.promote')!;

const rows = ['boiler', 'leak', 'bath', 'heat', 'drain', 'tap'].map((name, index) => ({
	id: `row${index}`,
	values: { name: `${name} repair` }
}));
const have = (value: unknown) => ({
	availability: 'have' as const,
	value: typeof value === 'string' ? value : JSON.stringify(value),
	note: null
});
const withList = (listRows = rows): SetupAnswers => ({ 'services.offered': have(listRows) });

describe('pick from an earlier list (A5f)', () => {
	it('takes its name box, wording and "list has a row" rule from the list', () => {
		expect(pick).toMatchObject({
			kind: 'pick',
			pickFrom: 'services.offered',
			minChoices: 3,
			maxChoices: 5,
			ordered: true,
			pickNameKey: 'name',
			pickListLabel: 'Add every service you offer',
			showIf: [{ factKey: 'services.offered', hasRows: true }]
		});
	});

	it('is asked only once its list holds a row', () => {
		expect(shownCatalogueFacts(catalogue, {}).has('website.promote')).toBe(false);
		expect(shownCatalogueFacts(catalogue, withList([])).has('website.promote')).toBe(false);
		expect(
			shownCatalogueFacts(catalogue, {
				'services.offered': { availability: 'not_yet', value: null, note: null }
			}).has('website.promote')
		).toBe(false);
		expect(shownCatalogueFacts(catalogue, withList()).has('website.promote')).toBe(true);
	});

	it('tells Jafar’s onboarding list the same rule', () => {
		const website = onboardingCatalogue(catalogue).find((section) => section.key === 'website');
		expect(website?.rules).toEqual([
			{ fact_key: 'website.promote', show_if: [{ fact_key: 'services.offered', has_rows: true }] }
		]);
	});

	it('accepts only rows the list holds now, each once, up to the most', () => {
		const answers = withList();
		expect(setupValueError(pick, JSON.stringify(['row2', 'row0', 'row1']), answers)).toBeNull();
		expect(setupValueError(pick, JSON.stringify(['row0', 'gone']), answers)).toMatch(
			/no longer in your list/
		);
		expect(setupValueError(pick, JSON.stringify(['row0', 'row0']), answers)).toMatch(/twice/);
		expect(setupValueError(pick, JSON.stringify(rows.map((row) => row.id)), answers)).toBe(
			'Pick no more than 5.'
		);
		expect(setupValueError(pick, '[]', answers)).toBe('Pick at least one.');
		expect(setupValueError(pick, 'boiler repair', answers)).toMatch(/could not be read/);
		// Without the list's answer nothing can be picked.
		expect(setupValueError(pick, JSON.stringify(['row0']), {})).toMatch(/no longer in your list/);
	});

	it('saves fewer than the fewest, and asks for the rest only at Mark as done', () => {
		const answers = { ...withList(), 'website.promote': have(['row0']) };
		expect(setupValueError(pick, JSON.stringify(['row0']), answers)).toBeNull();
		expect(setupAnswerShortfall(pick, answers)).toBe('Pick at least 3.');
		expect(
			setupAnswerShortfall(pick, { ...answers, 'website.promote': have(['row0', 'row1', 'row2']) })
		).toBeNull();
	});

	it('asks for every row when the list holds fewer than the fewest', () => {
		const two = rows.slice(0, 2);
		expect(
			setupAnswerShortfall(pick, { ...withList(two), 'website.promote': have(['row1', 'row0']) })
		).toBeNull();
		expect(setupPickInstruction({ minChoices: 3, maxChoices: 5 }, 2)).toBe('Pick all 2.');
	});

	it('stores the ids in the client’s order, not the words', () => {
		expect(storedSetupValue(pick, JSON.stringify(['row2', 'row0']))).toEqual(['row2', 'row0']);
	});

	it('drops a row the list no longer holds, keeping the order', () => {
		expect(keptSetupPickIds(['row2', 'row9', 'row0'], rows)).toEqual(['row2', 'row0']);
	});

	it('words what to pick plainly', () => {
		expect(setupPickInstruction({ minChoices: 3, maxChoices: 5 }, 6)).toBe('Pick 3 to 5.');
		expect(setupPickInstruction({ maxChoices: 2 }, 6)).toBe('Pick up to 2.');
		expect(setupPickInstruction({ minChoices: 3 }, 6)).toBe('Pick at least 3.');
		expect(setupPickInstruction({ maxChoices: 1 }, 6)).toBe('Pick one.');
		expect(setupPickInstruction({}, 6)).toBe('Pick as many as apply.');
	});

	it('names a row by its first box, or its place when that is empty', () => {
		expect(setupPickRowName(rows[0], 0, 'name')).toBe('boiler repair');
		expect(setupPickRowName({ id: 'x', values: {} }, 3, 'name')).toBe('Entry 4');
	});

	it('leaves out a pick whose list is not in the version', () => {
		const orphan = buildSetupCatalogue({
			...version,
			stages: [version.stages[1]]
		});
		expect(catalogueFacts(orphan).has('website.promote')).toBe(false);
	});

	it('refuses an unreadable pick without the list rule to read', () => {
		expect(parseSetupPick('{}', rows, {}).error).toMatch(/could not be read/);
	});
});
