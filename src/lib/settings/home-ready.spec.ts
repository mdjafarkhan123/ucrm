import { describe, expect, it } from 'vitest';
import { settingsReady } from './home-ready';

const home = {
	permissions: { communications_manage: true },
	readiness: {
		business_profile: { complete: true, missing: [] },
		business_hours_set: false,
		sms_registration: { readiness_state: 'under_review' },
		inquiry_alerts_owner_only: true,
		handover_delivered: false
	}
} as never;

describe('settingsReady', () => {
	it('counts done items and lists what is left, leaving out figures that did not load', () => {
		const result = settingsReady(home, undefined);
		expect(result.total).toBe(4);
		expect(result.done).toBe(1);
		expect(result.items.filter((item) => !item.done).map((item) => item.key)).toEqual([
			'hours',
			'texting',
			'alerts'
		]);
		expect(result.items.find((item) => item.key === 'texting')?.title).toBe('Texting is in review');
	});

	it('skips texting when the plan does not include it and uses the summary signals', () => {
		const result = settingsReady(
			{
				...(home as object),
				readiness: {
					...(home as { readiness: object }).readiness,
					sms_registration: { readiness_state: 'not_included' }
				}
			} as never,
			{
				signals: {
					logo: true,
					profile_details: true,
					tax_default: false,
					products: 3,
					team_members: 1,
					request_forms: 0,
					email_verified: true,
					payments_connected: false,
					review_link: true
				}
			}
		);
		expect(result.items.some((item) => item.key === 'texting')).toBe(false);
		expect(result.done).toBe(5);
		expect(result.total).toBe(11);
	});
});
