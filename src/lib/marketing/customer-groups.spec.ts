import { describe, expect, it } from 'vitest';
import {
	marketingExclusionReasonLabels,
	marketingExclusionReasons,
	marketingGroupRulesSchema
} from './customer-groups';

describe('marketing customer group rules', () => {
	it('accepts an empty rule set, which means every customer', () => {
		expect(marketingGroupRulesSchema.safeParse({ version: '1' }).success).toBe(true);
	});

	it('accepts the filters the first release offers', () => {
		const result = marketingGroupRulesSchema.safeParse({
			version: '1',
			lifecycle: ['customer'],
			tags: ['3f4f4cbb-3f1a-4f4a-9e0e-4e6d2b0f9a11'],
			cities: ['Manchester'],
			lead_sources: ['referral'],
			services: ['3f4f4cbb-3f1a-4f4a-9e0e-4e6d2b0f9a12'],
			work_type: 'recurring',
			last_completed_job: { mode: 'before_days', days: 180 },
			upcoming_work: false,
			include_client_ids: ['3f4f4cbb-3f1a-4f4a-9e0e-4e6d2b0f9a13'],
			exclude_client_ids: ['3f4f4cbb-3f1a-4f4a-9e0e-4e6d2b0f9a14']
		});
		expect(result.success).toBe(true);
	});

	it('refuses a filter the app does not offer, rather than ignoring it', () => {
		const result = marketingGroupRulesSchema.safeParse({
			version: '1',
			total_spend_over: 1000
		});
		expect(result.success).toBe(false);
	});

	it('refuses a rule set with no version, so an old saved shape can never be guessed at', () => {
		expect(marketingGroupRulesSchema.safeParse({ lifecycle: ['lead'] }).success).toBe(false);
	});

	it('refuses a "never completed a job" filter that also carries a day count', () => {
		const result = marketingGroupRulesSchema.safeParse({
			version: '1',
			last_completed_job: { mode: 'never', days: 30 }
		});
		expect(result.success).toBe(false);
	});

	it('refuses an id that is not a real id', () => {
		expect(marketingGroupRulesSchema.safeParse({ version: '1', tags: ['not-an-id'] }).success).toBe(
			false
		);
	});

	it('caps an explicit customer list so one request cannot carry unbounded input', () => {
		const tooMany = Array.from({ length: 501 }, () => '3f4f4cbb-3f1a-4f4a-9e0e-4e6d2b0f9a15');
		expect(
			marketingGroupRulesSchema.safeParse({ version: '1', include_client_ids: tooMany }).success
		).toBe(false);
	});

	it('has plain English for every exclusion reason the preview can report', () => {
		for (const reason of marketingExclusionReasons) {
			expect(marketingExclusionReasonLabels[reason]).toBeTruthy();
		}
	});
});
