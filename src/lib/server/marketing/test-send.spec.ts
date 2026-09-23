import { describe, expect, it, vi } from 'vitest';

import { MarketingEmailSubmissionError } from '$lib/server/communications/ses';
import type { OrganizationMarketingSendContext } from '$lib/server/marketing/dispatcher';
import { MarketingTestSendError, sendTestMarketingEmail } from './test-send';

const context: OrganizationMarketingSendContext = {
	business: {
		name: 'Ridgeway Contracting',
		addressLine1: '1 Main St',
		addressLine2: null,
		city: 'Springfield',
		region: null,
		postalCode: null,
		countryCode: 'US'
	},
	fromEmail: 'hello@news.ridgeway.example',
	fromName: 'Ridgeway Contracting',
	senderId: 'sender-1',
	receivingDomains: { 'domain-r': 'reply.ridgeway.example' },
	replyTo: { email: 'hello@mail.ridgeway.example', name: 'Ridgeway Contracting' },
	tenantName: 'ucrm-org-1',
	configurationSetName: 'ucrm-marketing-org-1'
};

const content = {
	version: '1' as const,
	subject: 'Hello {{customer_first_name}}',
	preview_text: '',
	blocks: [],
	cta: null
};

describe('sendTestMarketingEmail', () => {
	it('renders and sends a [Test]-prefixed email to the given recipient through the real send path', async () => {
		const buildContext = vi.fn().mockResolvedValue(context);
		const send = vi.fn().mockResolvedValue({ messageId: 'ses-message-1' });

		const result = await sendTestMarketingEmail('org-1', 'contractor@example.test', content, {
			buildContext,
			send
		});

		expect(result).toEqual({ messageId: 'ses-message-1' });
		expect(buildContext).toHaveBeenCalledWith('org-1');
		expect(send).toHaveBeenCalledTimes(1);
		const [message] = send.mock.calls[0];
		expect(message.to).toEqual({ email: 'contractor@example.test' });
		expect(message.subject).toBe('[Test] Hello Alex');
		expect(message.headers).toEqual([]);
		expect(message.tenantName).toBe('ucrm-org-1');
		expect(message.configurationSetName).toBe('ucrm-marketing-org-1');
		expect(message.htmlContent).toContain('Alex');
	});

	it('wraps a context-build failure in a friendly MarketingTestSendError', async () => {
		const buildContext = vi.fn().mockRejectedValue(new Error('no verified marketing domain'));
		const send = vi.fn();

		await expect(
			sendTestMarketingEmail('org-1', 'contractor@example.test', content, { buildContext, send })
		).rejects.toThrow(MarketingTestSendError);
		expect(send).not.toHaveBeenCalled();
	});

	it('lets a provider submission error propagate unwrapped', async () => {
		const buildContext = vi.fn().mockResolvedValue(context);
		const submissionError = new MarketingEmailSubmissionError(
			'Amazon SES rejected the send.',
			'cancelled',
			'ses_rejected'
		);
		const send = vi.fn().mockRejectedValue(submissionError);

		await expect(
			sendTestMarketingEmail('org-1', 'contractor@example.test', content, { buildContext, send })
		).rejects.toBe(submissionError);
	});
});
