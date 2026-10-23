import { describe, expect, it } from 'vitest';
import { diallingCode, formatRate, numberBand, numberReach } from './sms-destinations';
import { numberCard, readinessSummary, type ReadinessNumber } from './number-readiness';

function number(overrides: Partial<ReadinessNumber> = {}): ReadinessNumber {
	return {
		sender_id: 'sender-1',
		order_id: null,
		phone_number: '+12065550187',
		display_name: 'Main line',
		country_code: 'US',
		sender_type: 'long_code',
		number_type: 'local',
		lifecycle_state: 'ready',
		capabilities: { sms: true, mms: true, voice: true },
		is_default_sender: true,
		created_at: '2026-10-18T10:00:00Z',
		order: null,
		paperwork: null,
		toll_free_check: null,
		...overrides
	};
}

describe('numberReach', () => {
	it('lets a +1 number text the US and Canada, and others only their own country', () => {
		expect(numberReach('CA')).toEqual(['US', 'CA']);
		expect(numberReach('GB')).toEqual(['GB']);
	});
});

describe('numberBand', () => {
	it('names the +1 number that already texts Canada', () => {
		expect(numberBand([number()], 'CA')).toEqual({
			tone: 'success',
			title: 'Your Main line can text Canada',
			line: '+1 numbers text the US and Canada. Nothing to buy.'
		});
	});

	it('says a number is needed when none of the business numbers reach the country', () => {
		const band = numberBand(
			[number(), number({ country_code: 'GB', phone_number: '+447700900412', is_default_sender: false })],
			'AU'
		);
		expect(band.tone).toBe('warning');
		expect(band.title).toBe('You need a number in Australia');
		expect(band.line).toBe(
			'Your United States and United Kingdom numbers can’t text Australia. Add one here once it’s switched on.'
		);
	});

	it('falls back to the phone number when a number has no name', () => {
		expect(numberBand([number({ display_name: null })], 'US').title).toBe(
			'Your +1 (206) 555-0187 number can text United States'
		);
	});
});

describe('formatting', () => {
	it('keeps small rates readable and gives dialling codes', () => {
		expect(formatRate(0.08, 'USD')).toBe('$0.08');
		expect(formatRate(0.0083, 'USD')).toBe('$0.0083');
		expect(diallingCode('AU')).toBe('+61');
		expect(diallingCode('ZZ')).toBe('');
	});
});

describe('readinessSummary with asked-for countries', () => {
	const now = new Date('2026-10-22T12:00:00Z');

	it('adds an asked-for country as Setting up and drops one Uplift turned off', () => {
		const numbers = [number({ paperwork: null })];
		const cards = numbers.map((entry) => numberCard(entry, null, now));
		const summary = readinessSummary(numbers, cards, [
			{ country: 'AU', status: 'setting_up' },
			{ country: 'FR', status: 'off' }
		]);
		expect(summary.countries.map((country) => [country.code, country.ready])).toEqual([
			['AU', false],
			['US', cards[0].can_text]
		]);
	});

	it('shows a switched-on country as Ready only when a number can text it', () => {
		const numbers = [number()];
		const cards = numbers.map((entry) => ({ ...numberCard(entry, null, now), can_text: true }));
		const summary = readinessSummary(numbers, cards, [
			{ country: 'CA', status: 'ready' },
			{ country: 'AU', status: 'ready' }
		]);
		const ready = Object.fromEntries(summary.countries.map((country) => [country.code, country.ready]));
		expect(ready).toEqual({ AU: false, CA: true, US: true });
	});
});
