import { describe, expect, it } from 'vitest';
import { buildMarketingReadiness, type MarketingReadinessFacts } from './readiness';

const allGood: MarketingReadinessFacts = {
	hasVerifiedSendingDomain: true,
	hasEnabledSender: true,
	hasBusinessAddress: true,
	sendingPaused: false,
	allowanceState: 'numeric',
	hasConsentedCustomer: true
};

const codes = (facts: Partial<MarketingReadinessFacts>) =>
	buildMarketingReadiness({ ...allGood, ...facts }).reasons.map((reason) => reason.code);

describe('buildMarketingReadiness', () => {
	it('is ready when every fact holds', () => {
		expect(buildMarketingReadiness(allGood)).toEqual({ ready: true, reasons: [] });
	});

	it('treats an unlimited allowance as configured', () => {
		expect(codes({ allowanceState: 'unlimited' })).toEqual([]);
	});

	it('reports an unset allowance and gives the contractor no fix link', () => {
		const result = buildMarketingReadiness({ ...allGood, allowanceState: 'not_included' });
		expect(result.ready).toBe(false);
		expect(result.reasons).toEqual([
			expect.objectContaining({ code: 'allowance_not_configured', fix: null })
		]);
	});

	it('reports a pause without a fix link', () => {
		const [reason] = buildMarketingReadiness({ ...allGood, sendingPaused: true }).reasons;
		expect(reason).toMatchObject({ code: 'sending_paused', fix: null });
	});

	it('asks for the domain first and does not also ask for a sender', () => {
		expect(codes({ hasVerifiedSendingDomain: false, hasEnabledSender: false })).toEqual([
			'no_sending_domain'
		]);
	});

	it('asks for a sender once the domain is verified', () => {
		expect(codes({ hasEnabledSender: false })).toEqual(['no_sender']);
	});

	it('lists every problem in the order a person would fix them', () => {
		expect(
			codes({
				hasVerifiedSendingDomain: false,
				hasBusinessAddress: false,
				sendingPaused: true,
				allowanceState: 'not_included',
				hasConsentedCustomer: false
			})
		).toEqual([
			'no_sending_domain',
			'no_business_address',
			'sending_paused',
			'allowance_not_configured',
			'no_consented_customers'
		]);
	});
});
