import { describe, expect, it } from 'vitest';
import {
	SETUP_DISTANCE_UNITS,
	SETUP_DURATION_UNITS,
	defaultDistanceUnit,
	parseSetupChoices,
	parseSetupColours,
	parseSetupMeasure,
	parseSetupMoney,
	parseSetupNumber,
	parseSetupPercentage,
	parseSetupUrl,
	setupChoiceList
} from './answer-values';

const options = [{ value: 'cash' }, { value: 'card' }, { value: 'cheque' }];

describe('tick several', () => {
	it('keeps listed ticks in order', () => {
		expect(parseSetupChoices('["card","cash"]', { options, allowOther: false })).toEqual({
			value: ['card', 'cash'],
			error: null
		});
	});

	it('takes one entry of the client’s own words only when "Other" is offered', () => {
		expect(
			parseSetupChoices('["cash","Bank transfer"]', { options, allowOther: true }).value
		).toEqual(['cash', 'Bank transfer']);
		expect(
			parseSetupChoices('["Bank transfer"]', { options, allowOther: false }).error
		).not.toBeNull();
		expect(parseSetupChoices('["A","B"]', { options, allowOther: true }).error).not.toBeNull();
		expect(
			parseSetupChoices(JSON.stringify(['x'.repeat(101)]), { options, allowOther: true }).error
		).not.toBeNull();
	});

	it('holds to "up to N", and refuses nothing ticked, a tick twice, or a non-list', () => {
		const rules = { options, allowOther: true, maxChoices: 2 };
		expect(parseSetupChoices('["cash","card"]', rules).error).toBeNull();
		expect(parseSetupChoices('["cash","card","cheque"]', rules).error).toBe('Tick up to 2.');
		expect(parseSetupChoices('[]', rules).error).not.toBeNull();
		expect(parseSetupChoices('["cash","cash"]', rules).error).not.toBeNull();
		expect(parseSetupChoices('cash', rules).error).not.toBeNull();
		expect(parseSetupChoices('[1]', rules).error).not.toBeNull();
	});

	it('reads a saved list back, and nothing else as one', () => {
		expect(setupChoiceList('["cash"]')).toEqual(['cash']);
		expect(setupChoiceList('cash')).toBeNull();
		expect(setupChoiceList('[oops')).toBeNull();
	});
});

describe('web link', () => {
	it('adds https:// when it is left out, as people type addresses', () => {
		expect(parseSetupUrl('example.com').value).toBe('https://example.com');
		expect(parseSetupUrl('http://shop.example.co.uk/about').value).toBe(
			'http://shop.example.co.uk/about'
		);
	});

	it('refuses what a browser cannot open', () => {
		for (const bad of [
			'not a link',
			'localhost',
			'javascript:alert(1)',
			'ftp://example.com',
			'https://'
		])
			expect(parseSetupUrl(bad).error).not.toBeNull();
	});
});

describe('number and percentage', () => {
	it('accepts plain numbers up to two decimal places', () => {
		expect(parseSetupNumber('12').value).toBe(12);
		expect(parseSetupNumber('2.5').value).toBe(2.5);
		for (const bad of ['-1', '1.234', 'ten', '1e3', '1,000'])
			expect(parseSetupNumber(bad).error).not.toBeNull();
	});

	it('keeps a percentage between 0 and 100', () => {
		expect(parseSetupPercentage('0').value).toBe(0);
		expect(parseSetupPercentage('12.5').value).toBe(12.5);
		expect(parseSetupPercentage('100.01').error).not.toBeNull();
	});
});

describe('money', () => {
	it('keeps the amount as written, with its currency', () => {
		expect(parseSetupMoney('{"amount":"99.50","currency":"GBP"}').value).toEqual({
			amount: '99.50',
			currency: 'GBP'
		});
	});

	it('follows the currency’s own decimal places', () => {
		expect(parseSetupMoney('{"amount":"99.505","currency":"USD"}').error).not.toBeNull();
		expect(parseSetupMoney('{"amount":"150.5","currency":"JPY"}').error).toBe(
			'Enter a whole amount, like 150.'
		);
	});

	it('refuses an amount with no currency, or no amount', () => {
		expect(parseSetupMoney('{"amount":"10"}').error).not.toBeNull();
		expect(parseSetupMoney('{"amount":"","currency":"EUR"}').error).not.toBeNull();
		expect(parseSetupMoney('10').error).not.toBeNull();
	});
});

describe('distance and time', () => {
	it('keeps an amount above zero with a listed unit', () => {
		expect(
			parseSetupMeasure('{"amount":25,"unit":"mi"}', SETUP_DISTANCE_UNITS, 'distance').value
		).toEqual({
			amount: 25,
			unit: 'mi'
		});
		expect(
			parseSetupMeasure('{"amount":1.5,"unit":"hours"}', SETUP_DURATION_UNITS, 'time').error
		).toBeNull();
		expect(
			parseSetupMeasure('{"amount":0,"unit":"km"}', SETUP_DISTANCE_UNITS, 'distance').error
		).not.toBeNull();
		expect(
			parseSetupMeasure('{"amount":5,"unit":"hours"}', SETUP_DISTANCE_UNITS, 'distance').error
		).not.toBeNull();
		expect(
			parseSetupMeasure('{"amount":"5","unit":"km"}', SETUP_DISTANCE_UNITS, 'distance').error
		).not.toBeNull();
	});

	it('suggests miles only where people use them', () => {
		expect(defaultDistanceUnit('US')).toBe('mi');
		expect(defaultDistanceUnit('GB')).toBe('mi');
		expect(defaultDistanceUnit('CA')).toBe('km');
		expect(defaultDistanceUnit(null)).toBe('km');
	});
});

describe('colours', () => {
	it('keeps six-digit codes in capitals', () => {
		expect(parseSetupColours('["#1a73e8","#FFFFFF"]').value).toEqual(['#1A73E8', '#FFFFFF']);
	});

	it('refuses short codes, names, repeats, none and too many', () => {
		for (const bad of [
			'["#fff"]',
			'["blue"]',
			'["#000000","#000000"]',
			'[]',
			JSON.stringify(Array.from({ length: 9 }, (_, i) => `#00000${i}`))
		])
			expect(parseSetupColours(bad).error).not.toBeNull();
	});
});
