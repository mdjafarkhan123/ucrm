import { describe, expect, it, vi } from 'vitest';
import { OperationalEmailSubmissionError } from './brevo';
import {
	drainCommunicationEmailQueue,
	EMAIL_WORKER_NAME,
	processClaimedEmail,
	runMonitoredEmailWake,
	type CommunicationWorkerClient
} from './email-worker';

const claim = {
	outbox_event_id: 'outbox-1',
	delivery_intent_id: 'intent-1',
	claim_token: 'claim-1',
	recipient_email: 'customer@example.com',
	subject: 'Your job update',
	html_content: '<p>Your job is scheduled.</p>',
	text_content: 'Your job is scheduled.',
	logical_send_key: 'job-update-1',
	sender_id: 'sender-1',
	sender_email: 'service@mail.ridgeway.example',
	sender_name: 'Ridgeway'
};

function clientWithClaim(
	value: typeof claim | undefined,
	attachments: {
		file_name: string;
		mime_type: string;
		byte_size: number;
		object_key: string;
	}[] = []
) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'claim_communication_outbox_event')
			return { data: value ? [value] : [], error: null };
		if (name === 'list_communication_outbound_attachments')
			return { data: attachments, error: null };
		if (name === 'finalize_communication_outbox_event')
			return { data: [{ outbox_status: 'submitted' }], error: null };
		return { data: null, error: { message: 'Unexpected RPC.' } };
	});
	return { client: { rpc } as CommunicationWorkerClient, rpc };
}

describe('processClaimedEmail', () => {
	it('returns idle without sending when no row is claimable', async () => {
		const { client } = clientWithClaim(undefined);
		const send = vi.fn();

		await expect(processClaimedEmail({ client, send })).resolves.toEqual({ status: 'idle' });
		expect(send).not.toHaveBeenCalled();
	});

	it('submits one claimed intent and finalizes it with the same lease', async () => {
		const { client, rpc } = clientWithClaim(claim);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		await expect(processClaimedEmail({ client, send })).resolves.toEqual({
			status: 'submitted',
			intentId: 'intent-1'
		});
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				from: { email: claim.sender_email, name: claim.sender_name },
				intentId: 'intent-1'
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_outbox_event',
			expect.objectContaining({
				target_outbox_event_id: 'outbox-1',
				target_claim_token: 'claim-1',
				target_outcome: 'submitted',
				target_provider_message_id: 'provider-message-1'
			})
		);
	});

	it('reads each listed attachment and hands Brevo base64 content', async () => {
		const attachmentRow = {
			file_name: 'quote.pdf',
			mime_type: 'application/pdf',
			byte_size: 4,
			object_key: 'org-1/outbound-email-attachments/i/quote.pdf'
		};
		const { client } = clientWithClaim(claim, [attachmentRow]);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });
		const readAttachment = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3, 4]));

		await expect(processClaimedEmail({ client, send, readAttachment })).resolves.toMatchObject({
			status: 'submitted'
		});

		expect(readAttachment).toHaveBeenCalledWith(attachmentRow.object_key);
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				attachments: [{ name: 'quote.pdf', content: Buffer.from([1, 2, 3, 4]).toString('base64') }]
			})
		);
	});

	it('sends with an empty attachment list when the intent has no attachments', async () => {
		const { client } = clientWithClaim(claim);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		await processClaimedEmail({ client, send });

		expect(send).toHaveBeenCalledWith(expect.objectContaining({ attachments: [] }));
	});

	it.each([
		['retry', 'brevo_http_503'],
		['cancelled', 'brevo_http_400'],
		['submission_unknown', 'brevo_network_unknown']
	] as const)('records a %s provider outcome without a second send', async (outcome, code) => {
		const { client, rpc } = clientWithClaim(claim);
		const send = vi
			.fn()
			.mockRejectedValue(new OperationalEmailSubmissionError('Provider outcome.', outcome, code));

		await expect(processClaimedEmail({ client, send })).resolves.toMatchObject({
			status: outcome,
			intentId: 'intent-1'
		});
		expect(send).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_outbox_event',
			expect.objectContaining({ target_outcome: outcome, target_failure_code: code })
		);
	});
});

describe('drainCommunicationEmailQueue', () => {
	// A client that quarantines a fixed count and hands back a queue of claims, then empties.
	function drainingClient(claimCount: number, stale: number) {
		let remaining = claimCount;
		const rpc = vi.fn(async (name: string) => {
			if (name === 'quarantine_stale_communication_claims') return { data: stale, error: null };
			if (name === 'claim_communication_outbox_event') {
				if (remaining <= 0) return { data: [], error: null };
				remaining -= 1;
				return { data: [{ ...claim, outbox_event_id: `outbox-${remaining}` }], error: null };
			}
			if (name === 'list_communication_outbound_attachments') return { data: [], error: null };
			if (name === 'finalize_communication_outbox_event')
				return { data: [{ outbox_status: 'submitted' }], error: null };
			return { data: null, error: { message: 'Unexpected RPC.' } };
		});
		return { client: { rpc } as CommunicationWorkerClient, rpc };
	}

	it('quarantines once, then drains every queued intent', async () => {
		const { client, rpc } = drainingClient(3, 2);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		const result = await drainCommunicationEmailQueue({ client, send, concurrency: 1 });

		expect(result).toMatchObject({
			staleClaimsQuarantined: 2,
			claimed: 3,
			submitted: 3,
			stoppedBy: 'idle'
		});
		expect(
			rpc.mock.calls.filter(([name]) => name === 'quarantine_stale_communication_claims')
		).toHaveLength(1);
		expect(send).toHaveBeenCalledTimes(3);
	});
});

describe('runMonitoredEmailWake', () => {
	// A client that answers the lease/ledger RPCs and an empty drain, with knobs for the lease outcome, a
	// forced ledger-write error, and a slow claim used to trip the route deadline.
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
			if (name === 'quarantine_stale_communication_claims') return { data: 0, error: null };
			if (name === 'claim_communication_outbox_event') {
				if (options.claimDelayMs)
					await new Promise((resolve) => setTimeout(resolve, options.claimDelayMs));
				return { data: [], error: null };
			}
			return { data: null, error: { message: `Unexpected RPC ${name}.` } };
		});
		return { client: { rpc } as CommunicationWorkerClient, rpc };
	}

	const wake = { wakeCorrelationId: 'wake-1', nowIso: () => '2026-09-09T00:00:00.000Z' };

	it('reports already_running and never drains when the lease is held', async () => {
		const { client, rpc } = monitoredClient({ leaseToken: null });

		await expect(runMonitoredEmailWake({ client, ...wake })).resolves.toEqual({
			outcome: 'already_running'
		});
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain('claim_communication_outbox_event');
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
			'release_communication_worker_lease'
		);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'already_running', p_worker_name: EMAIL_WORKER_NAME })
		);
	});

	it('drains under the lease, records the outcome with counts, and releases the lease', async () => {
		const { client, rpc } = monitoredClient({});

		await expect(runMonitoredEmailWake({ client, ...wake, concurrency: 1 })).resolves.toMatchObject({
			outcome: 'idle',
			claimed: 0,
			stoppedBy: 'idle'
		});
		expect(rpc).toHaveBeenCalledWith(
			'release_communication_worker_lease',
			expect.objectContaining({ p_lease_token: 'lease-1' })
		);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'idle', p_claimed: 0 })
		);
	});

	it('reports route_deadline without releasing the lease when the drain overruns', async () => {
		const { client, rpc } = monitoredClient({ claimDelayMs: 60 });

		await expect(
			runMonitoredEmailWake({ client, ...wake, routeDeadlineMs: 5 })
		).resolves.toEqual({ outcome: 'route_deadline' });
		expect(rpc.mock.calls.map(([name]) => name)).not.toContain(
			'release_communication_worker_lease'
		);
		expect(rpc).toHaveBeenCalledWith(
			'record_communication_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'route_deadline' })
		);
	});

	it('still returns the drain outcome when the ledger write fails', async () => {
		const { client } = monitoredClient({ recordError: true });

		await expect(
			runMonitoredEmailWake({ client, ...wake, concurrency: 1 })
		).resolves.toMatchObject({ outcome: 'idle' });
	});
});
