import { describe, expect, it } from 'vitest';
import {
	providerWaitAside,
	providerWaitLabel,
	providerWaitOpen,
	providerWaitOwnerLabel,
	providerWaitsFor,
	providerWaitsFromRows
} from './provider-waits';

describe('providerWaitsFor', () => {
	it('offers only the waits of services the package includes', () => {
		expect(providerWaitsFor(['website', 'reviews'])).toEqual(['website_address']);
		expect(providerWaitsFor(['calls_texting', 'google_profile'])).toEqual([
			'google_profile',
			'texting_approval',
			'number_transfer'
		]);
		expect(providerWaitsFor([])).toEqual([]);
	});
});

describe('labels', () => {
	it('names the provider in the client’s words and Jafar’s', () => {
		expect(providerWaitLabel('google_profile', 'in_review')).toBe('Being reviewed by Google');
		expect(providerWaitLabel('number_transfer', 'submitted')).toBe(
			'Sent to your old phone company'
		);
		expect(providerWaitOwnerLabel('number_transfer', 'submitted')).toBe(
			'Sent to their old phone company'
		);
		expect(providerWaitLabel('texting_approval', 'action_needed')).toBe('You need to do something');
		expect(providerWaitOwnerLabel('texting_approval', 'action_needed')).toBe(
			'They need to do something'
		);
	});

	it('says the time is not Uplift’s only while the provider has it', () => {
		expect(providerWaitAside('google_profile', 'in_review')).toBe(
			"This is up to Google — it isn't counted in Uplift's 7–10 days."
		);
		expect(providerWaitAside('texting_approval', 'submitted')).toContain('the phone carriers');
		for (const status of [
			'waiting_for_access',
			'action_needed',
			'approved',
			'unavailable'
		] as const)
			expect(providerWaitAside('google_profile', status)).toBeNull();
	});

	it('counts a wait as open until approved or ruled out', () => {
		expect(providerWaitOpen('in_review')).toBe(true);
		expect(providerWaitOpen('action_needed')).toBe(true);
		expect(providerWaitOpen('approved')).toBe(false);
		expect(providerWaitOpen('unavailable')).toBe(false);
	});
});

describe('providerWaitsFromRows', () => {
	it('keeps the fixed order and drops anything unknown', () => {
		const at = '2026-10-05T10:00:00Z';
		expect(
			providerWaitsFromRows([
				{ wait_key: 'website_address', status: 'approved', note: null, updated_at: at },
				{ wait_key: 'fax_line', status: 'approved', note: null, updated_at: at },
				{
					wait_key: 'google_profile',
					status: 'action_needed',
					note: 'Type the code',
					updated_at: at
				}
			])
		).toEqual([
			{ key: 'google_profile', status: 'action_needed', note: 'Type the code', updated_at: at },
			{ key: 'website_address', status: 'approved', note: null, updated_at: at }
		]);
	});
});
