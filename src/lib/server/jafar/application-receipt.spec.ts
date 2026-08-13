import { beforeEach, describe, expect, it, vi } from 'vitest';
import { sendApplicationReceipt } from './application-receipt';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';

vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));

const mockedEnqueue = vi.mocked(enqueueEmailDelivery);

const DEFAULT_TEMPLATE = {
	subject_published: 'Thanks for applying, {{package_name}} at {{price}}',
	body_published: '<p>Payment: {{payment_instructions}}</p>'
};

function clientWith(options: {
	snapshot?: { display_name?: string; price_usd_cents?: number } | null;
	template?: { subject_published: string | null; body_published: string | null } | null;
} = {}) {
	const snapshot = 'snapshot' in options ? options.snapshot : { display_name: 'Growth', price_usd_cents: 4900 };
	const template = 'template' in options ? options.template : DEFAULT_TEMPLATE;

	return {
		from: (table: string) => {
			if (table === 'platform_onboarding_applications') {
				return {
					select: () => ({
						eq: () => ({
							single: async () => ({ data: snapshot ? { package_snapshot: snapshot } : null, error: null })
						})
					})
				};
			}
			if (table === 'platform_message_templates') {
				return {
					select: () => ({
						eq: () => ({ maybeSingle: async () => ({ data: template, error: null }) })
					})
				};
			}
			throw new Error(`unexpected table ${table}`);
		}
	};
}

const baseParams = {
	applicationId: 'app-1',
	recipientEmail: 'jordan@ridgeway.example',
	paymentInstructions: 'Pay via bank transfer within 5 days.'
};

describe('sendApplicationReceipt', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('renders the published application_receipt template from the immutable package snapshot and queues it', async () => {
		const client = clientWith();

		await sendApplicationReceipt(client as never, baseParams);

		expect(mockedEnqueue).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				templateKey: 'application_receipt',
				target: { targetKind: 'onboarding_application', targetId: 'app-1' },
				idempotencyKey: 'application:app-1:receipt',
				recipientEmail: 'jordan@ridgeway.example',
				subject: 'Thanks for applying, Growth at $49/mo',
				htmlContent: '<p>Payment: Pay via bank transfer within 5 days.</p>',
				textContent: 'Payment: Pay via bank transfer within 5 days.'
			})
		);
	});

	it('sends the published wording and ignores an unpublished draft edit', async () => {
		const client = clientWith({
			template: {
				...DEFAULT_TEMPLATE,
				subject_draft: 'Draft subject nobody approved',
				body_draft: '<p>Draft body nobody approved</p>'
			} as never
		});

		await sendApplicationReceipt(client as never, baseParams);

		const queued = mockedEnqueue.mock.calls[0][1];
		expect(queued.subject).toBe('Thanks for applying, Growth at $49/mo');
		expect(queued.htmlContent).not.toContain('Draft');
	});

	it('throws before queuing anything when the receipt template has not been published', async () => {
		const client = clientWith({ template: { subject_published: null, body_published: null } });

		await expect(sendApplicationReceipt(client as never, baseParams)).rejects.toThrow(
			'has not been published yet'
		);
		expect(mockedEnqueue).not.toHaveBeenCalled();
	});
});
