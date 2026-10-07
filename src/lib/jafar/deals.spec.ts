import { describe, expect, it } from 'vitest';
import {
	OPEN_DEAL_STAGES,
	PRICING_FOLLOW_UP_DAYS,
	daysSince,
	isOverdue,
	latestShare,
	monthlyValue,
	suggestedNextStep,
	type DealPriceShare
} from './deals';

const share = (shared_at: string, package_name: string): DealPriceShare => ({
	shared_at,
	package_slug: package_name.toLowerCase(),
	package_name,
	monthly_price_usd_cents: 12_900,
	yearly_price_usd_cents: null,
	offers: {},
	link: `https://example.com/packages/${package_name.toLowerCase()}`,
	actor_email: 'owner@example.com'
});

describe('Deal next steps', () => {
	const today = new Date(2026, 9, 7);

	it('suggests a step and date for every open stage', () => {
		for (const stage of OPEN_DEAL_STAGES) {
			const step = suggestedNextStep(stage, 'Acme Plumbing', today);
			expect(step.text, stage).toContain('Acme Plumbing');
			expect(step.due_on >= '2026-10-07', stage).toBe(true);
		}
	});

	it('follows up three days after pricing is shared and a month after Later', () => {
		expect(PRICING_FOLLOW_UP_DAYS).toBe(3);
		expect(suggestedNextStep('pricing_shared', 'Acme', today).due_on).toBe('2026-10-10');
		expect(suggestedNextStep('later', 'Acme', today).due_on).toBe('2026-11-06');
		expect(suggestedNextStep('interested', 'Acme', today).due_on).toBe('2026-10-07');
	});

	it('crosses month and year ends on the calendar, not by adding hours', () => {
		expect(suggestedNextStep('pricing_shared', 'Acme', new Date(2026, 11, 30)).due_on).toBe(
			'2027-01-02'
		);
	});
});

describe('Deal dates and values', () => {
	it('is overdue only once the due day has passed', () => {
		expect(isOverdue('2026-10-06', '2026-10-07')).toBe(true);
		expect(isOverdue('2026-10-07', '2026-10-07')).toBe(false);
		expect(isOverdue(null, '2026-10-07')).toBe(false);
	});

	it('counts whole days in a stage and never below zero', () => {
		const now = new Date('2026-10-07T12:00:00Z');
		expect(daysSince('2026-10-07T11:00:00Z', now)).toBe(0);
		expect(daysSince('2026-09-28T12:00:00Z', now)).toBe(9);
		expect(daysSince('2026-10-08T12:00:00Z', now)).toBe(0);
	});

	it('shows a monthly value only when there is one', () => {
		expect(monthlyValue(null)).toBeNull();
		expect(monthlyValue(12_900)).toMatch(/129.*\/mo$/);
	});

	it('takes only the newest share’s packages, in the order they were chosen', () => {
		const deal = {
			shares: [
				share('2026-10-07T10:00:00Z', 'Pro'),
				share('2026-10-07T10:00:00Z', 'Starter'),
				share('2026-10-01T10:00:00Z', 'Growth')
			]
		};
		expect(latestShare(deal).map((item) => item.package_name)).toEqual(['Pro', 'Starter']);
		expect(latestShare({ shares: [] })).toEqual([]);
	});
});
