import { describe, expect, it } from 'vitest';
import {
	HOURS_EXCEPTIONS_MAX,
	parseSetupHours,
	parseSetupHoursExceptions,
	setupHoursFromBusinessHours
} from './hours';

const closed = { open: false, all_day: false, periods: [] };
const week = (days: Record<number, unknown>) =>
	JSON.stringify({
		mode: 'weekly',
		days: [0, 1, 2, 3, 4, 5, 6].map((weekday) => days[weekday] ?? closed)
	});

describe('parseSetupHours', () => {
	it('accepts a split day, a 24-hour day and a shift past midnight', () => {
		const result = parseSetupHours(
			week({
				1: {
					open: true,
					all_day: false,
					periods: [
						['08:00', '12:00'],
						['13:00', '17:00']
					]
				},
				2: { open: true, all_day: true, periods: [] },
				5: { open: true, all_day: false, periods: [['18:00', '02:00']] }
			})
		);
		expect(result.error).toBeNull();
		expect(result.value).toMatchObject({ mode: 'weekly' });
	});

	it('accepts appointment only without a week', () => {
		expect(parseSetupHours('{"mode":"appointment_only"}').value).toEqual({
			mode: 'appointment_only'
		});
	});

	it('asks for at least one open day', () => {
		expect(parseSetupHours(week({})).error).toMatch(/at least one day/);
	});

	it('refuses a week it cannot make sense of', () => {
		expect(parseSetupHours('not json').error).not.toBeNull();
		expect(parseSetupHours('{"mode":"weekly","days":[]}').error).not.toBeNull();
		// An open day with no times, a closed day with times, and a period that opens and closes together.
		expect(
			parseSetupHours(week({ 1: { open: true, all_day: false, periods: [] } })).error
		).not.toBeNull();
		expect(
			parseSetupHours(week({ 1: { open: false, all_day: false, periods: [['09:00', '17:00']] } }))
				.error
		).not.toBeNull();
		expect(
			parseSetupHours(week({ 1: { open: true, all_day: false, periods: [['09:00', '09:00']] } }))
				.error
		).not.toBeNull();
		expect(
			parseSetupHours(week({ 1: { open: true, all_day: false, periods: [['9am', '5pm']] } })).error
		).not.toBeNull();
	});
});

describe('parseSetupHoursExceptions', () => {
	it('keeps a closed day and a short day, in date order, with tidy names', () => {
		const result = parseSetupHoursExceptions(
			JSON.stringify([
				{ date: '2027-01-01', name: ' New Year ', closed: true },
				{
					date: '2026-12-24',
					name: 'Christmas Eve',
					closed: false,
					opens: '09:00',
					closes: '13:00'
				}
			])
		);
		expect(result.value).toEqual([
			{ date: '2026-12-24', name: 'Christmas Eve', closed: false, opens: '09:00', closes: '13:00' },
			{ date: '2027-01-01', name: 'New Year', closed: true, opens: null, closes: null }
		]);
	});

	it('refuses the same date twice, an impossible date and an open day without times', () => {
		const twice = [
			{ date: '2026-12-25', name: '', closed: true },
			{ date: '2026-12-25', name: '', closed: true }
		];
		expect(parseSetupHoursExceptions(JSON.stringify(twice)).error).toMatch(/same date/);
		expect(
			parseSetupHoursExceptions(JSON.stringify([{ date: '2026-13-01', name: '', closed: true }]))
				.error
		).not.toBeNull();
		expect(
			parseSetupHoursExceptions(JSON.stringify([{ date: '2026-12-25', name: '', closed: false }]))
				.error
		).not.toBeNull();
	});

	it('holds the list to its limit', () => {
		const many = Array.from({ length: HOURS_EXCEPTIONS_MAX + 1 }, (_, index) => ({
			date: `2027-${String(1 + Math.floor(index / 28)).padStart(2, '0')}-${String(1 + (index % 28)).padStart(2, '0')}`,
			name: '',
			closed: true
		}));
		expect(parseSetupHoursExceptions(JSON.stringify(many)).error).toMatch(/dates/);
	});
});

describe('setupHoursFromBusinessHours', () => {
	const row = (
		weekday: number,
		opens_at: string | null,
		closes_at: string | null,
		all = false
	) => ({
		weekday,
		period_index: 0,
		is_open: true,
		is_open_24h: all,
		opens_at,
		closes_at
	});

	it('offers nothing while the business has not set its hours', () => {
		expect(setupHoursFromBusinessHours('not_configured', [])).toBeNull();
	});

	it('turns the saved week into an answer the wizard accepts', () => {
		const hours = setupHoursFromBusinessHours('weekly', [
			row(1, '08:00:00', '17:00:00'),
			row(6, null, null, true)
		]);
		expect(hours).not.toBeNull();
		expect(parseSetupHours(JSON.stringify(hours)).error).toBeNull();
		expect(hours).toMatchObject({ mode: 'weekly' });
		if (hours?.mode !== 'weekly') return;
		expect(hours.days[1]).toEqual({ open: true, all_day: false, periods: [['08:00', '17:00']] });
		expect(hours.days[6]).toEqual({ open: true, all_day: true, periods: [] });
		expect(hours.days[0].open).toBe(false);
	});

	it('carries appointment only across', () => {
		expect(setupHoursFromBusinessHours('appointment_only', [])).toEqual({
			mode: 'appointment_only'
		});
	});
});
