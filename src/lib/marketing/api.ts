import type { MarketingReadiness } from './readiness';

export const marketingReadinessKey = ['marketing', 'readiness'] as const;

// A refusal keeps its status and reason so the page can tell "not in your plan" from "not your permission"
// instead of calling both a failure.
export type MarketingApiError = Error & { status?: number; reason?: string };

export async function fetchMarketingReadiness(): Promise<MarketingReadiness> {
	const response = await fetch('/api/marketing/readiness');
	if (!response.ok) {
		const result = (await response.json().catch(() => ({}))) as { error?: string; reason?: string };
		const failure = new Error(
			result.error ?? 'Marketing readiness could not be checked.'
		) as MarketingApiError;
		failure.status = response.status;
		failure.reason = result.reason;
		throw failure;
	}
	return response.json();
}
