import { describe, expect, it, vi } from 'vitest';
import { TwilioSmsSubmissionError } from './twilio';
import {
	drainCommunicationSmsQueue,
	processClaimedSms,
	runMonitoredSmsWake,
	SMS_WORKER_NAME,
	type CommunicationWorkerClient,
	type ResolveSmsCredentials
} from './sms-worker';

const claim = {
	outbox_event_id: 'outbox-1',
	delivery_intent_id: 'intent-1',
	organization_id: 'org-1',
	twilio_account_id: 'acct-1',
	subaccount_sid: 'AC00000000000000000000000000000001',
	messaging_service_sid: 'MG00000000000000000000000000000001',
	claim_token: 'claim-1',
	attempt_number: 1,
	recipient_phone: '+15551234567',
	sender_phone: '+15005550006',
	body: 'Your job is confirmed.',
	encoding: 'gsm7',
	segment_count: 1
};

const credentials: ResolveSmsCredentials = async () => ({
	apiKeySid: 'SK00000000000000000000000000000001',
	apiKeySecret: 'secret'
});

function clientWithClaim(value: typeof claim | undefined, attachments: unknown[] = []) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'claim_communication_sms_outbox_event')
			return { data: value ? [value] : [], error: null };
		if (name === 'list_communication_outbound_attachments')
			return { data: attachments, error: null };
		if (name === 'finalize_communication_sms_outbox_event')
			return { data: [{ outbox_status: 'submitted' }], error: null };
		return { data: null, error: { message: `Unexpected RPC ${name}.` } };
	});
	return { client: { rpc } as CommunicationWorkerClient, rpc };
}

describe('processClaimedSms', () => {
	it('returns idle without sending when no row is claimable', async () => {
		const { client } = clientWithClaim(undefined);
		const submit = vi.fn();

		await expect(
			processClaimedSms({ client, submit, resolveCredentials: credentials })
		).resolves.toEqual({ status: 'idle' });
		expect(submit).not.toHaveBeenCalled();
	});

	it('submits one claimed SMS and finalizes it with the same lease', async () => {
		const { client, rpc } = clientWithClaim(claim);
		const submit = vi.fn().mockResolvedValue({ providerMessageId: 'SMabc' });

		await expect(
			processClaimedSms({ client, submit, resolveCredentials: credentials })
		).resolves.toEqual({ status: 'submitted', intentId: 'intent-1' });

		expect(submit).toHaveBeenCalledWith(
			expect.objectContaining({
				subaccountSid: claim.subaccount_sid,
				messagingServiceSid: claim.messaging_service_sid,
				from: claim.sender_phone,
				to: claim.recipient_phone,
				body: claim.body,
				apiKeySid: 'SK00000000000000000000000000000001'
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_sms_outbox_event',
			expect.objectContaining({
				target_outbox_event_id: 'outbox-1',
				target_claim_token: 'claim-1',
				target_outcome: 'submitted',
				target_provider_message_id: 'SMabc'
			})
		);
	});

	it('presigns and forwards media URLs for a claimed SMS with a picture attached', async () => {
		const { client } = clientWithClaim(claim, [
			{
				file_name: 'job-photo.jpg',
				mime_type: 'image/jpeg',
				byte_size: 12_345,
				object_key: 'org-1/outbound-sms-attachments/job-photo.jpg'
			}
		]);
		const submit = vi.fn().mockResolvedValue({ providerMessageId: 'SMabc' });
		const presignMedia = vi.fn().mockResolvedValue('https://r2.example/signed-url');

		await expect(
			processClaimedSms({ client, submit, resolveCredentials: credentials, presignMedia })
		).resolves.toEqual({ status: 'submitted', intentId: 'intent-1' });

		expect(presignMedia).toHaveBeenCalledWith(
			'org-1/outbound-sms-attachments/job-photo.jpg',
			'job-photo.jpg'
		);
		expect(submit).toHaveBeenCalledWith(
			expect.objectContaining({ mediaUrls: ['https://r2.example/signed-url'] })
		);
	});

	it.each([
		['retry', 'twilio_http_429'],
		['cancelled', 'twilio_http_400'],
		['submission_unknown', 'twilio_network_unknown']
	] as const)('records a %s provider outcome without a second send', async (outcome, code) => {
		const { client, rpc } = clientWithClaim(claim);
		const submit = vi
			.fn()
			.mockRejectedValue(new TwilioSmsSubmissionError('Provider outcome.', outcome, code));

		await expect(
			processClaimedSms({ client, submit, resolveCredentials: credentials })
		).resolves.toMatchObject({ status: outcome, intentId: 'intent-1' });
		expect(submit).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_sms_outbox_event',
			expect.objectContaining({ target_outcome: outcome, target_failure_code: code })
		);
	});

	it('retries without contacting the provider when the sending credentials cannot be resolved', async () => {
		const { client, rpc } = clientWithClaim(claim);
		const submit = vi.fn();
		const resolveCredentials = vi.fn().mockRejectedValue(new Error('key missing'));

		await expect(processClaimedSms({ client, submit, resolveCredentials })).resolves.toMatchObject({
			status: 'retry',
			intentId: 'intent-1'
		});
		expect(submit).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_sms_outbox_event',
			expect.objectContaining({
				target_outcome: 'retry',
				target_failure_code: 'twilio_credentials_unavailable'
			})
		);
	});

	it('treats an unexpected non-Twilio error during send as an unknown submission', async () => {
		const { client, rpc } = clientWithClaim(claim);
		const submit = vi.fn().mockRejectedValue(new Error('boom'));

		await expect(
			processClaimedSms({ client, submit, resolveCredentials: credentials })
		).resolves.toMatchObject({ status: 'submission_unknown' });
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_sms_outbox_event',
			expect.objectContaining({ target_outcome: 'submission_unknown' })
		);
	});
});

describe('drainCommunicationSmsQueue', () => {
	function drainingClient(claimCount: number, stale: number) {
		let remaining = claimCount;
		const rpc = vi.fn(async (name: string) => {
			if (name === 'quarantine_stale_communication_sms_claims') return { data: stale, error: null };
			if (name === 'claim_communication_sms_outbox_event') {
				if (remaining <= 0) return { data: [], error: null };
				remaining -= 1;
				return { data: [{ ...claim, outbox_event_id: `outbox-${remaining}` }], error: null };
			}
			if (name === 'list_communication_outbound_attachments') return { data: [], error: null };
			if (name === 'finalize_communication_sms_outbox_event')
				return { data: [{ outbox_status: 'submitted' }], error: null };
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return { client: { rpc } as CommunicationWorkerClient, rpc };
	}

	it('quarantines once, then drains every queued SMS', async () => {
		const { client, rpc } = drainingClient(3, 2);
		const submit = vi.fn().mockResolvedValue({ providerMessageId: 'SMabc' });

		const result = await drainCommunicationSmsQueue({
			client,
			submit,
			resolveCredentials: credentials,
			concurrency: 1
		});

		expect(result).toMatchObject({
			staleClaimsQuarantined: 2,
			claimed: 3,
			submitted: 3,
			stoppedBy: 'idle'
		});
		expect(
			rpc.mock.calls.filter(([name]) => name === 'quarantine_stale_communication_sms_claims')
		).toHaveLength(1);
		expect(submit).toHaveBeenCalledTimes(3);
	});
});

describe('runMonitoredSmsWake', () => {
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
			if (name === 'quarantine_stale_communication_sms_claims') return { data: 0, error: null };
			if (name === 'claim_communication_sms_outbox_event') {
				if (options.claimDelayMs)
					await new Promise((resolve) => setTimeout(resolve, options.claimDelayMs));
				return { data: [], error: null };
			}
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return { client: { rpc } as CommunicationWorkerClient, rpc };
	}

	const wake = { wakeCorrelationId: 'wake-1', nowIso: () => '2026-09-15T00:00:00.000Z' };

	it('reports already_running and never drains when the lease is held', async () => {
		const { client, rpc } = monitoredClient({ leaseToken: null });

		await expect(runMonitoredSmsWake({ client, ...wake })).resolves.toEqual({
			outcome: 'already_running'
		});
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
			'claim_communication_sms_outbox_event'
		);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({
				p_route_outcome: 'already_running',
				p_worker_name: SMS_WORKER_NAME
			})
		);
	});

	it('drains under the lease, records the outcome, and releases the lease', async () => {
		const { client, rpc } = monitoredClient({});

		await expect(runMonitoredSmsWake({ client, ...wake, concurrency: 1 })).resolves.toMatchObject({
			outcome: 'idle',
			claimed: 0,
			stoppedBy: 'idle'
		});
		expect(rpc).toHaveBeenCalledWith(
			'release_communication_worker_lease',
			expect.objectContaining({ p_lease_token: 'lease-1', p_worker_name: SMS_WORKER_NAME })
		);
	});

	it('reports route_deadline without releasing the lease when the drain overruns', async () => {
		const { client, rpc } = monitoredClient({ claimDelayMs: 60 });

		await expect(runMonitoredSmsWake({ client, ...wake, routeDeadlineMs: 5 })).resolves.toEqual({
			outcome: 'route_deadline'
		});
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
			'release_communication_worker_lease'
		);
	});

	it('still returns the drain outcome when the ledger write fails', async () => {
		const { client } = monitoredClient({ recordError: true });

		await expect(runMonitoredSmsWake({ client, ...wake, concurrency: 1 })).resolves.toMatchObject({
			outcome: 'idle'
		});
	});
});
