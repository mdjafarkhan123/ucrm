import { describe, expect, it } from 'vitest';
import { conversionRateCard, newRequestsCard } from './metrics';

const period = (created: number, converted: number) => ({ new: created, converted });

describe('Requests list 30-day cards', () => {
	it('counts new requests and compares them with the 30 days before', () => {
		expect(newRequestsCard(period(3, 0), period(10, 2))).toEqual({
			value: '3',
			note: 'Past 30 days · ↓ 70% vs the 30 days before'
		});
		expect(newRequestsCard(period(12, 0), period(8, 0)).note).toBe(
			'Past 30 days · ↑ 50% vs the 30 days before'
		);
		expect(newRequestsCard(period(4, 0), period(4, 0)).note).toBe(
			'Past 30 days · same as the 30 days before'
		);
	});

	it('shows no trend when the 30 days before had nothing to compare', () => {
		expect(newRequestsCard(period(5, 0), period(0, 0))).toEqual({
			value: '5',
			note: 'Past 30 days'
		});
		expect(conversionRateCard(period(4, 1), period(0, 0)).note).toBe('Past 30 days');
		expect(conversionRateCard(period(4, 1), period(3, 0)).note).toBe('Past 30 days');
	});

	it('works out the conversion rate as a share of the new requests, trend as a percent change', () => {
		// 50% now against 25% before is a 100% rise, as Jobber writes it.
		expect(conversionRateCard(period(4, 2), period(4, 1))).toEqual({
			value: '50%',
			note: 'Past 30 days · ↑ 100% vs the 30 days before'
		});
		expect(conversionRateCard(period(3, 0), period(10, 2))).toEqual({
			value: '0%',
			note: 'Past 30 days · ↓ 100% vs the 30 days before'
		});
	});

	it('shows a dash rather than 0% when there were no new requests', () => {
		expect(conversionRateCard(period(0, 0), period(6, 3))).toEqual({
			value: '—',
			note: 'No new requests in the past 30 days'
		});
	});
});
