import { describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: { APP_URL: 'https://app.example.com' } }));

import { MarketingEmailSubmissionError } from '$lib/server/communications/ses';
import {
	drainMarketingCampaignQueue,
	MARKETING_WORKER_NAME,
	processClaimedMarketingRecipient,
	runMonitoredMarketingWake,
	type CampaignSendContext,
	type MarketingWorkerClient
} from './dispatcher';

const recipient = {
	recipient_id: 'recipient-1',
	campaign_id: 'campaign-1',
	organization_id: 'org-1',
	claim_token: 'claim-1',
	client_id: 'client-1',
	client_contact_method_id: 'method-1',
	recipient_email: 'customer@example.test',
	display_name: 'Alex Rivera'
};

const context: CampaignSendContext = {
	content: {
		version: '1',
		subject: 'Hello {{customer_first_name}}',
		preview_text: '',
		blocks: [],
		cta: null
	},
	serviceNames: {},
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
	replyTo: { email: 'hello@mail.ridgeway.example', name: 'Ridgeway Contracting' },
	tenantName: 'ucrm-org-1',
	configurationSetName: 'ucrm-marketing-org-1'
};

function clientWithClaim(value: typeof recipient | undefined) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'claim_marketing_campaign_recipient')
			return { data: value ? [value] : [], error: null };
		if (name === 'issue_client_marketing_unsubscribe_link')
			return { data: { unsubscribe_link_id: 'link-1' }, error: null };
		if (name === 'finalize_marketing_campaign_send')
			return { data: [{ recipient_status: 'submitted', campaign_status: 'sending' }], error: null };
		return { data: null, error: { message: `Unexpected RPC ${name}.` } };
	});
	return { client: { rpc } as MarketingWorkerClient, rpc };
}

describe('processClaimedMarketingRecipient', () => {
	it('returns idle without sending when no row is claimable', async () => {
		const { client } = clientWithClaim(undefined);
		const send = vi.fn();
		const loadContext = vi.fn().mockResolvedValue(context);

		await expect(processClaimedMarketingRecipient({ client, send, loadContext })).resolves.toEqual({
			status: 'idle'
		});
		expect(send).not.toHaveBeenCalled();
	});

	it('renders, sends, and finalizes one claimed recipient', async () => {
		const { client, rpc } = clientWithClaim(recipient);
		const send = vi.fn().mockResolvedValue({ messageId: 'ses-message-1' });
		const loadContext = vi.fn().mockResolvedValue(context);

		await expect(processClaimedMarketingRecipient({ client, send, loadContext })).resolves.toEqual({
			status: 'submitted',
			recipientId: 'recipient-1'
		});

		expect(loadContext).toHaveBeenCalledWith('org-1', 'campaign-1');
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				from: { email: context.fromEmail, name: context.fromName },
				to: { email: recipient.recipient_email },
				replyTo: context.replyTo,
				subject: 'Hello Alex',
				tenantName: context.tenantName,
				configurationSetName: context.configurationSetName
			})
		);
		// RFC 8058 one-click headers, keyed by the same unsubscribe token embedded in the body link.
		expect(send.mock.calls[0][0].headers).toEqual(
			expect.arrayContaining([expect.objectContaining({ name: 'List-Unsubscribe' })])
		);
		expect(rpc).toHaveBeenCalledWith(
			'issue_client_marketing_unsubscribe_link',
			expect.objectContaining({
				target_organization_id: 'org-1',
				target_client_contact_method_id: 'method-1'
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_marketing_campaign_send',
			expect.objectContaining({
				target_recipient_id: 'recipient-1',
				target_claim_token: 'claim-1',
				target_outcome: 'submitted',
				target_provider_message_id: 'ses-message-1'
			})
		);
	});

	it('takes only the first whitespace token as customer_first_name', async () => {
		const { client } = clientWithClaim({ ...recipient, display_name: '  Priya   Singh Jr ' });
		const send = vi.fn().mockResolvedValue({ messageId: 'ses-message-1' });
		const loadContext = vi.fn().mockResolvedValue({
			...context,
			content: { ...context.content, subject: '{{customer_first_name}}' }
		});

		await processClaimedMarketingRecipient({ client, send, loadContext });

		expect(send).toHaveBeenCalledWith(expect.objectContaining({ subject: 'Priya' }));
	});

	it.each([
		['retry', 'ses_500'],
		['cancelled', 'ses_400'],
		['submission_unknown', 'ses_network_unknown']
	] as const)('records a %s provider outcome without a second send', async (outcome, code) => {
		const { client, rpc } = clientWithClaim(recipient);
		const send = vi
			.fn()
			.mockRejectedValue(new MarketingEmailSubmissionError('Provider outcome.', outcome, code));
		const loadContext = vi.fn().mockResolvedValue(context);

		await expect(
			processClaimedMarketingRecipient({ client, send, loadContext })
		).resolves.toMatchObject({ status: outcome, recipientId: 'recipient-1' });
		expect(send).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_marketing_campaign_send',
			expect.objectContaining({ target_outcome: outcome, target_failure_code: code })
		);
	});

	it('finalizes as submission_unknown when the context cannot be loaded', async () => {
		const { client, rpc } = clientWithClaim(recipient);
		const send = vi.fn();
		const loadContext = vi
			.fn()
			.mockRejectedValue(new Error('The Marketing identity is not ready.'));

		await expect(
			processClaimedMarketingRecipient({ client, send, loadContext })
		).resolves.toMatchObject({ status: 'submission_unknown' });
		expect(send).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_marketing_campaign_send',
			expect.objectContaining({ target_outcome: 'submission_unknown' })
		);
	});
});

describe('drainMarketingCampaignQueue', () => {
	function drainingClient(claimCount: number, stale: number) {
		let remaining = claimCount;
		const rpc = vi.fn(async (name: string) => {
			if (name === 'quarantine_stale_marketing_campaign_claims')
				return { data: stale, error: null };
			if (name === 'claim_marketing_campaign_recipient') {
				if (remaining <= 0) return { data: [], error: null };
				remaining -= 1;
				return { data: [{ ...recipient, recipient_id: `recipient-${remaining}` }], error: null };
			}
			if (name === 'issue_client_marketing_unsubscribe_link')
				return { data: { unsubscribe_link_id: 'link-1' }, error: null };
			if (name === 'finalize_marketing_campaign_send')
				return {
					data: [{ recipient_status: 'submitted', campaign_status: 'sending' }],
					error: null
				};
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return { client: { rpc } as MarketingWorkerClient, rpc };
	}

	it('quarantines once, then drains every queued recipient', async () => {
		const { client, rpc } = drainingClient(3, 1);
		const send = vi.fn().mockResolvedValue({ messageId: 'ses-message-1' });
		const loadContext = vi.fn().mockResolvedValue(context);

		const result = await drainMarketingCampaignQueue({ client, send, loadContext, concurrency: 1 });

		expect(result).toMatchObject({
			staleClaimsQuarantined: 1,
			claimed: 3,
			submitted: 3,
			stoppedBy: 'idle'
		});
		expect(
			rpc.mock.calls.filter(([name]) => name === 'quarantine_stale_marketing_campaign_claims')
		).toHaveLength(1);
		expect(send).toHaveBeenCalledTimes(3);
	});
});

describe('runMonitoredMarketingWake', () => {
	function monitoredClient(options: {
		leaseToken?: string | null;
		recordError?: boolean;
		claimDelayMs?: number;
	}) {
		const rpc = vi.fn(async (name: string) => {
			if (name === 'acquire_communication_worker_lease')
				return { data: 'leaseToken' in options ? options.leaseToken : 'lease-1', error: null };
			if (name === 'release_communication_worker_lease') return { data: true, error: null };
			if (name === 'record_communication_worker_wake_result')
				return { data: null, error: options.recordError ? { message: 'ledger down' } : null };
			if (name === 'quarantine_stale_marketing_campaign_claims') return { data: 0, error: null };
			if (name === 'claim_marketing_campaign_recipient') {
				if (options.claimDelayMs)
					await new Promise((resolve) => setTimeout(resolve, options.claimDelayMs));
				return { data: [], error: null };
			}
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return { client: { rpc } as MarketingWorkerClient, rpc };
	}

	const wake = { wakeCorrelationId: 'wake-1', nowIso: () => '2026-09-22T00:00:00.000Z' };

	it('reports already_running and never drains when the lease is held', async () => {
		const { client, rpc } = monitoredClient({ leaseToken: null });

		await expect(runMonitoredMarketingWake({ client, ...wake })).resolves.toEqual({
			outcome: 'already_running'
		});
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
			'claim_marketing_campaign_recipient'
		);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({
				p_route_outcome: 'already_running',
				p_worker_name: MARKETING_WORKER_NAME
			})
		);
	});

	it('drains under the lease, records the outcome with counts, and releases the lease', async () => {
		const { client, rpc } = monitoredClient({});

		await expect(
			runMonitoredMarketingWake({ client, ...wake, concurrency: 1 })
		).resolves.toMatchObject({ outcome: 'idle', claimed: 0, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith(
			'release_communication_worker_lease',
			expect.objectContaining({ p_lease_token: 'lease-1' })
		);
	});

	it('reports route_deadline without releasing the lease when the drain overruns', async () => {
		const { client, rpc } = monitoredClient({ claimDelayMs: 60 });

		await expect(
			runMonitoredMarketingWake({ client, ...wake, routeDeadlineMs: 5 })
		).resolves.toEqual({ outcome: 'route_deadline' });
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
			'release_communication_worker_lease'
		);
	});
});
