import { describe, expect, it } from 'vitest';
import { groupRuleChips } from './group-rule-chips';

describe('groupRuleChips', () => {
	it('says each condition in plain words, in the condition list order', () => {
		const chips = groupRuleChips({
			version: '1',
			upcoming_work: false,
			last_completed_job: { mode: 'before_days', days: 180 },
			lifecycle: ['customer']
		});
		expect(chips.map((chip) => chip.text)).toEqual([
			'Are customers',
			'Last job over 6 months ago',
			'Have no upcoming work'
		]);
	});

	it('turns days into weeks, months and years', () => {
		const text = (days: number) =>
			groupRuleChips({ version: '1', last_completed_job: { mode: 'within_days', days } })[0].text;
		expect(text(14)).toBe('Last job within 2 weeks');
		expect(text(30)).toBe('Last job within 1 month');
		expect(text(730)).toBe('Last job within 2 years');
		expect(text(45)).toBe('Last job within 45 days');
	});

	it('names services once known and counts them until then', () => {
		const rules = { version: '1' as const, services: ['a', 'b', 'c'] };
		expect(groupRuleChips(rules)[0].text).toBe('Used 3 services');
		expect(groupRuleChips(rules, { a: 'Boiler repair', b: 'Gutters', c: 'Roof' })[0].text).toBe(
			'Used Boiler repair, Gutters +1'
		);
	});

	it('gives an empty group no chips', () => {
		expect(groupRuleChips({ version: '1' })).toEqual([]);
	});
});
