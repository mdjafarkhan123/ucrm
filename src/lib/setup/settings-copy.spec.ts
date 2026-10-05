import { describe, expect, it } from 'vitest';
import type { SetupAnswers } from '$lib/setup/catalogue';
import type { SetupHelpAnswer } from '$lib/setup/help';
import { businessHoursRows, setupSettingProposals, type SetupSendAnswers } from './settings-copy';

const have = (value: string) => ({ availability: 'have' as const, value, note: null });

const BUSINESS: SetupAnswers = {
	'business.public_name': have('Raad LTD'),
	'business.trade': have('Plumber'),
	'business.public_phone': have('+44 20 7946 0958'),
	'business.country': have('GB'),
	'business.address_line1': have('1 High Street'),
	'business.address_city': have('Leeds'),
	'business.address_postal_code': have('LS1 1AA'),
	'business.address_public': have('no'),
	'business.timezone': have('Europe/London'),
	'business.currency': have('GBP')
};

const send = (number: number, answers: SetupAnswers): SetupSendAnswers => ({
	number,
	submitted_at: `2026-10-0${number}T10:00:00.000Z`,
	answers
});

const ALL = new Set([
	...Object.keys(BUSINESS),
	'business.address_line2',
	'business.address_region',
	'business.availability',
	'business.hours'
]);

function weekly(open: [string, string][][]) {
	return JSON.stringify({
		mode: 'weekly',
		days: open.map((periods) => ({ open: periods.length > 0, all_day: false, periods }))
	});
}

describe('setupSettingProposals', () => {
	it('fills each setting from an accepted answer, with when it was sent', () => {
		const proposals = setupSettingProposals({
			sends: [send(1, BUSINESS)],
			acceptedKeys: ALL,
			help: {}
		});
		expect(proposals.name).toEqual({ value: 'Raad LTD', told_at: '2026-10-01T10:00:00.000Z' });
		expect(proposals.currency_code?.value).toBe('GBP');
		expect(proposals.address_is_public?.value).toBe(false);
		expect(proposals.address?.value).toEqual({
			address_line1: '1 High Street',
			address_line2: null,
			city: 'Leeds',
			region: null,
			postal_code: 'LS1 1AA',
			country_code: 'GB'
		});
	});

	it('copies nothing from a section Uplift has not accepted', () => {
		expect(
			setupSettingProposals({ sends: [send(1, BUSINESS)], acceptedKeys: new Set(), help: {} })
		).toEqual({});
	});

	it('dates an unchanged answer from the first send that held it, a changed one from its own', () => {
		const later = { ...BUSINESS, 'business.trade': have('Electrician') };
		const proposals = setupSettingProposals({
			sends: [send(1, BUSINESS), send(2, BUSINESS), send(3, later)],
			acceptedKeys: ALL,
			help: {}
		});
		expect(proposals.name?.told_at).toBe('2026-10-01T10:00:00.000Z');
		expect(proposals.trade).toEqual({ value: 'Electrician', told_at: '2026-10-03T10:00:00.000Z' });
	});

	it('uses Uplift’s answer to a help request, dated when Uplift recorded it', () => {
		const help: Record<string, SetupHelpAnswer> = {
			'business.public_phone': {
				value: '+44 113 000 0000',
				note: null,
				lines: [],
				recorded_by_email: 'jafar@example.com',
				recorded_at: '2026-10-05T09:00:00.000Z'
			}
		};
		const answers = {
			...BUSINESS,
			'business.public_phone': { availability: 'need_help' as const, value: null, note: null }
		};
		const proposals = setupSettingProposals({ sends: [send(1, answers)], acceptedKeys: ALL, help });
		expect(proposals.phone).toEqual({
			value: '+44 113 000 0000',
			told_at: '2026-10-05T09:00:00.000Z'
		});
	});

	it('leaves a help request Uplift has not answered, and an answer the client has not got yet', () => {
		const answers = {
			...BUSINESS,
			'business.public_phone': { availability: 'need_help' as const, value: null, note: null },
			'business.trade': { availability: 'not_yet' as const, value: null, note: null }
		};
		const proposals = setupSettingProposals({
			sends: [send(1, answers)],
			acceptedKeys: ALL,
			help: {}
		});
		expect(proposals.phone).toBeUndefined();
		expect(proposals.trade).toBeUndefined();
	});

	it('follows a reused answer to the one it reuses', () => {
		const answers = {
			...BUSINESS,
			'business.public_phone': have(JSON.stringify({ same_as: 'business.contact_phone' })),
			'business.contact_phone': have('+44 7700 900123')
		};
		const proposals = setupSettingProposals({
			sends: [send(1, answers)],
			acceptedKeys: ALL,
			help: {}
		});
		expect(proposals.phone?.value).toBe('+44 7700 900123');
	});

	it('copies no address without a street, a town and a country', () => {
		const answers = {
			...BUSINESS,
			'business.address_line1': { availability: 'not_yet' as const, value: null, note: null }
		};
		const proposals = setupSettingProposals({
			sends: [send(1, answers)],
			acceptedKeys: ALL,
			help: {}
		});
		expect(proposals.address).toBeUndefined();
	});

	it('turns the hours answer into Business Hours rows, and 24/7 into all-day days', () => {
		const nine = [['09:00', '17:00']] as [string, string][];
		const answers = {
			...BUSINESS,
			'business.hours': have(weekly([[], nine, nine, nine, nine, nine, []]))
		};
		const proposals = setupSettingProposals({
			sends: [send(1, answers)],
			acceptedKeys: ALL,
			help: {}
		});
		const hours = proposals.hours?.value as { mode: string; rows: unknown[] };
		expect(hours.mode).toBe('weekly');
		expect(hours.rows[0]).toEqual({
			weekday: 0,
			period_index: 0,
			is_open: false,
			is_open_24h: false,
			opens_at: null,
			closes_at: null
		});
		expect(hours.rows[1]).toEqual({
			weekday: 1,
			period_index: 0,
			is_open: true,
			is_open_24h: false,
			opens_at: '09:00',
			closes_at: '17:00'
		});

		const always = setupSettingProposals({
			sends: [send(1, { ...answers, 'business.availability': have('always') })],
			acceptedKeys: ALL,
			help: {}
		});
		const rows = (always.hours?.value as { rows: { is_open_24h: boolean }[] }).rows;
		expect(rows).toHaveLength(7);
		expect(rows.every((row) => row.is_open_24h)).toBe(true);
	});
});

describe('businessHoursRows', () => {
	it('refuses periods Settings would refuse: overlapping or out of order', () => {
		const day = (periods: [string, string][]) => ({ open: true, all_day: false, periods });
		const closed = { open: false, all_day: false, periods: [] };
		const week = (first: ReturnType<typeof day>) => ({
			mode: 'weekly' as const,
			days: [first, closed, closed, closed, closed, closed, closed]
		});
		expect(
			businessHoursRows(
				week(
					day([
						['09:00', '12:00'],
						['11:00', '17:00']
					])
				)
			)
		).toBeNull();
		expect(
			businessHoursRows(
				week(
					day([
						['13:00', '17:00'],
						['09:00', '12:00']
					])
				)
			)
		).toBeNull();
		expect(
			businessHoursRows(
				week(
					day([
						['09:00', '12:00'],
						['13:00', '17:00']
					])
				)
			)
		).not.toBeNull();
	});
});
