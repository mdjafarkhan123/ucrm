// What stops a contractor sending Marketing email right now, in plain words, each with the one screen that
// fixes it. Shared by the server (which decides) and the page (which shows it), so the wording lives once.

import type { MarketingWarmupProgress } from './warmup';

export type MarketingReadinessCode =
	| 'no_sending_domain'
	| 'no_sender'
	| 'no_business_address'
	| 'sending_paused'
	| 'allowance_not_configured'
	| 'no_consented_customers';

export type MarketingReadinessReason = {
	code: MarketingReadinessCode;
	title: string;
	detail: string;
	// null when the contractor cannot fix it themselves (a pause or a plan limit).
	fix: {
		label: string;
		href: '/settings/communications/email' | '/settings/business-profile' | '/clients';
	} | null;
};

export type MarketingReadiness = {
	ready: boolean;
	reasons: MarketingReadinessReason[];
	// How far the Marketing sending domain has warmed up; null when it could not be read.
	warmup?: MarketingWarmupProgress | null;
};

export type MarketingReadinessFacts = {
	hasVerifiedSendingDomain: boolean;
	hasEnabledSender: boolean;
	hasBusinessAddress: boolean;
	sendingPaused: boolean;
	allowanceState: 'not_included' | 'numeric' | 'unlimited';
	hasConsentedCustomer: boolean;
};

// One reason per real fix, in the order a person would fix them. A missing sender is only reported once the
// domain is verified, because adding a sender before its domain is verified is not a useful next step.
export function buildMarketingReadiness(facts: MarketingReadinessFacts): MarketingReadiness {
	const reasons: MarketingReadinessReason[] = [];

	if (!facts.hasVerifiedSendingDomain) {
		reasons.push({
			code: 'no_sending_domain',
			title: 'Verify your sending domain',
			detail: 'Marketing email is sent from your own domain once it is verified.',
			fix: { label: 'Set up email', href: '/settings/communications/email' }
		});
	} else if (!facts.hasEnabledSender) {
		reasons.push({
			code: 'no_sender',
			title: 'Add a sender address',
			detail: 'Choose the address your Marketing email comes from.',
			fix: { label: 'Set up email', href: '/settings/communications/email' }
		});
	}

	if (!facts.hasBusinessAddress) {
		reasons.push({
			code: 'no_business_address',
			title: 'Add a business address',
			detail: 'Every Marketing email must show your business address.',
			fix: { label: 'Open business profile', href: '/settings/business-profile' }
		});
	}

	if (facts.sendingPaused) {
		reasons.push({
			code: 'sending_paused',
			title: 'Marketing email is temporarily paused to protect delivery',
			detail: 'Email sending is paused for your account. It resumes once the problem is resolved.',
			fix: null
		});
	}

	if (facts.allowanceState === 'not_included') {
		reasons.push({
			code: 'allowance_not_configured',
			title: 'Marketing allowance not configured',
			detail: 'Your plan does not include a Marketing email allowance yet.',
			fix: null
		});
	}

	if (!facts.hasConsentedCustomer) {
		reasons.push({
			code: 'no_consented_customers',
			title: 'No eligible customers have marketing consent',
			detail:
				'Customers can agree on a public form, or you can record a real preference on their page.',
			fix: { label: 'Open customers', href: '/clients' }
		});
	}

	return { ready: reasons.length === 0, reasons };
}
