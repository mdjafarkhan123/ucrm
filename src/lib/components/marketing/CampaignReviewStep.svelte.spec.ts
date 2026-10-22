import { page } from 'vitest/browser';
import { describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClient } from '@tanstack/query-core';
import { QueryClientProvider } from '@tanstack/svelte-query';
import CampaignReviewStep from './CampaignReviewStep.svelte';
import { emptyMarketingCampaignContent } from '$lib/marketing/campaign-content';
import { emptyMarketingDeliveryOptions, type MarketingDeliveryOptions } from '$lib/marketing/api';

// The owner is who sees the Send button; the Review step reads the role from the page data.
vi.mock('$app/state', () => ({ page: { data: { organization: { role: 'owner' } } } }));

const options: MarketingDeliveryOptions = {
	...emptyMarketingDeliveryOptions,
	sender: { id: 's1', email_address: 'office@example.com', display_name: 'Raad LTD Office' },
	business_website: 'example.com',
	allowance: { state: 'numeric', value: 100, is_unlimited: false }
};

function renderStep(overrides: Partial<MarketingDeliveryOptions>, cta: 'website' | null) {
	const content = {
		...structuredClone(emptyMarketingCampaignContent),
		cta: cta ? { type: cta } : null
	};
	const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		CampaignReviewStep,
		{
			props: {
				content,
				campaignId: null,
				name: 'Spring offer',
				goal: null,
				customerGroupId: null,
				groups: [],
				options: { ...options, ...overrides },
				isPending: false,
				isError: false,
				onRetry: vi.fn(),
				onBack: vi.fn(),
				onSend: vi.fn()
			} as never
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } } as never
	);
}

// The Send button's words are the count once known, else "Send now".
const sendButton = () => page.getByRole('button', { name: /^Send now$|^Send to/ });

describe('CampaignReviewStep Send button', () => {
	it('is on when the sender and the button are both set', async () => {
		renderStep({}, 'website');
		await expect.element(sendButton()).not.toBeDisabled();
	});

	it('is off while there is no verified sender', async () => {
		renderStep({ sender: null }, 'website');
		await expect.element(sendButton()).toBeDisabled();
	});

	it('is off while no button was chosen', async () => {
		renderStep({}, null);
		await expect.element(sendButton()).toBeDisabled();
	});
});
