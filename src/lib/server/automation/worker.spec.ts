import { describe, expect, it, vi } from 'vitest';
import {
	AUTOMATION_WORKER_NAME,
	drainAutomationEvents,
	drainAutomationWork,
	runMonitoredAutomationWake,
	type AutomationWorkerClient
} from './worker';

type ClaimItem = {
	work_item_id: string;
	claim_token: string;
	organization_id: string;
	enrollment_id: string;
	step_index: number;
	attempts: number;
};

function item(id: string, org = 'org-1'): ClaimItem {
	return {
		work_item_id: id,
		claim_token: `claim-${id}`,
		organization_id: org,
		enrollment_id: `enrollment-${id}`,
		step_index: 0,
		attempts: 0
	};
}

// A scripted worker client. Successive intake counts and claim batches are consumed in order; once a queue is
// exhausted the RPC answers as an empty/idle queue, exactly as the database would when nothing is due.
function workClient(
	options: {
		intake?: number[];
		claims?: ClaimItem[][];
		advance?: (id: string) => string;
		advanceError?: boolean;
		perform?: (id: string) => string;
		performError?: boolean;
		performSms?: (id: string) => string;
		performSmsError?: boolean;
		performMessage?: (id: string) => string;
		reviewDraft?: unknown;
		performReview?: (id: string) => string;
		performAppointment?: (id: string) => string;
		remindersDue?: number;
		fallbacks?: number;
		claimError?: string;
		retryError?: string;
		recordError?: boolean;
		claimDelayMs?: number;
	} = {}
) {
	const intake = [...(options.intake ?? [0])];
	const claims = [...(options.claims ?? [])];
	const rpc = vi.fn(async (name: string, args?: Record<string, unknown>) => {
		if (name === 'intake_automation_events') {
			return { data: intake.length > 0 ? intake.shift()! : 0, error: null };
		}
		if (name === 'claim_automation_work_items') {
			if (options.claimError) return { data: null, error: { message: options.claimError } };
			if (options.claimDelayMs)
				await new Promise((resolve) => setTimeout(resolve, options.claimDelayMs));
			return { data: claims.length > 0 ? claims.shift()! : [], error: null };
		}
		if (name === 'advance_automation_work_item') {
			if (options.advanceError) return { data: null, error: { message: 'db exploded' } };
			const id = String(args?.p_work_item_id);
			return { data: options.advance ? options.advance(id) : 'completed', error: null };
		}
		if (name === 'perform_automation_email_effect') {
			if (options.performError) return { data: null, error: { message: 'send path exploded' } };
			const id = String(args?.p_work_item_id);
			return { data: options.perform ? options.perform(id) : 'action_sent', error: null };
		}
		if (name === 'perform_automation_sms_effect') {
			if (options.performSmsError) return { data: null, error: { message: 'sms path exploded' } };
			const id = String(args?.p_work_item_id);
			return { data: options.performSms ? options.performSms(id) : 'action_sent', error: null };
		}
		if (name === 'perform_automation_inquiry_message_effect') {
			const id = String(args?.p_work_item_id);
			return {
				data: options.performMessage ? options.performMessage(id) : 'action_sent',
				error: null
			};
		}
		if (name === 'automation_review_request_draft') {
			return { data: options.reviewDraft ?? null, error: null };
		}
		if (name === 'perform_automation_review_request_effect') {
			const id = String(args?.p_work_item_id);
			return {
				data: options.performReview ? options.performReview(id) : 'action_sent',
				error: null
			};
		}
		if (name === 'perform_automation_appointment_email_effect') {
			const id = String(args?.p_work_item_id);
			return {
				data: options.performAppointment ? options.performAppointment(id) : 'action_sent',
				error: null
			};
		}
		if (name === 'emit_due_appointment_reminders') {
			return { data: options.remindersDue ?? 0, error: null };
		}
		if (name === 'claim_review_reminders') return { data: [], error: null };
		if (name === 'process_automation_sms_email_fallbacks') {
			return { data: options.fallbacks ?? 0, error: null };
		}
		if (name === 'retry_automation_work_item') {
			if (options.retryError) return { data: null, error: { message: options.retryError } };
			return { data: true, error: null };
		}
		if (name === 'record_automation_worker_wake_result')
			return { data: null, error: options.recordError ? { message: 'ledger down' } : null };
		return { data: null, error: { message: `Unexpected RPC ${name}.` } };
	});
	return { client: { rpc } as AutomationWorkerClient, rpc };
}

// A fixed access link so an action effect never touches env or real crypto in a unit test.
const stubLink = () => ({ url: 'https://app.example.com/q/token', tokenHash: '\\xdeadbeef' });

// Returns each supplied value once, then repeats the last one. Lets a test drive the drain's deadline checks.
function scriptedNow(values: number[]) {
	let i = 0;
	return () => (i < values.length ? values[i++] : values[values.length - 1]);
}

describe('drainAutomationWork', () => {
	it('reports idle and moves nothing when no events and no work are due', async () => {
		const { client, rpc } = workClient({ intake: [0], claims: [] });

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toEqual({
			remindersDue: 0,
			eventsProcessed: 0,
			claimed: 0,
			waited: 0,
			completed: 0,
			sent: 0,
			cancelled: 0,
			parked: 0,
			retried: 0,
			fallbacks: 0,
			reviewReminders: 0,
			stoppedBy: 'idle'
		});
		expect(rpc).toHaveBeenCalledWith('claim_automation_work_items', expect.anything());
	});

	it('takes in events first, then claims a fair batch and advances each item until idle', async () => {
		const { client, rpc } = workClient({
			intake: [2],
			claims: [[item('a'), item('b')], [item('c')]]
		});

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({
			eventsProcessed: 2,
			claimed: 3,
			completed: 3,
			stoppedBy: 'idle'
		});
		// Intake runs before the work drain so an event that arrives this wake reaches its first step.
		const order = rpc.mock.calls.map(([name]) => name);
		expect(order.indexOf('intake_automation_events')).toBeLessThan(
			order.indexOf('claim_automation_work_items')
		);
		expect(rpc).toHaveBeenCalledWith(
			'claim_automation_work_items',
			expect.objectContaining({ p_per_organization_cap: 5, p_worker: AUTOMATION_WORKER_NAME })
		);
	});

	it('finds due visit reminders before intake, so their events are enrolled in the same wake', async () => {
		const { client, rpc } = workClient({ remindersDue: 3, intake: [3], claims: [] });

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({ remindersDue: 3, eventsProcessed: 3 });
		const order = rpc.mock.calls.map(([name]) => name);
		expect(order.indexOf('emit_due_appointment_reminders')).toBeLessThan(
			order.indexOf('intake_automation_events')
		);
		expect(rpc).toHaveBeenCalledWith('emit_due_appointment_reminders', { p_limit: 200 });
	});

	it('runs a due visit reminder through its own email effect', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a'), item('b')]],
			advance: () => 'action_due_appointment_email',
			performAppointment: (id) => (id === 'a' ? 'action_sent' : 'action_cancelled')
		});

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({ claimed: 2, sent: 1, cancelled: 1 });
		expect(rpc).toHaveBeenCalledWith('perform_automation_appointment_email_effect', {
			p_work_item_id: 'a',
			p_claim_token: 'claim-a'
		});
		expect(rpc).not.toHaveBeenCalledWith('perform_automation_email_effect', expect.anything());
	});

	it('stops at the claim cap and never claims past it', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a'), item('b')], [item('c')]]
		});

		const result = await drainAutomationWork({ client, now: () => 0, maxClaims: 2, batchSize: 10 });

		expect(result).toMatchObject({ claimed: 2, stoppedBy: 'max_claims' });
		// Only one claim call, and its batch size was clamped to the remaining cap, not the configured size.
		const claimCalls = rpc.mock.calls.filter(([name]) => name === 'claim_automation_work_items');
		expect(claimCalls).toHaveLength(1);
		expect(claimCalls[0][1]).toMatchObject({ p_batch_size: 2 });
	});

	it('stops when the time budget is spent, keeping the work already claimed', async () => {
		const { client } = workClient({ intake: [0], claims: [[item('a'), item('b')]] });

		const result = await drainAutomationWork({
			client,
			// deadline calc, intake check, review reminder check, iter-1 check (in budget), iter-2 check (over).
			now: scriptedNow([0, 0, 0, 0, 2000]),
			timeBudgetMs: 1000
		});

		expect(result).toMatchObject({ claimed: 2, completed: 2, stoppedBy: 'time_budget' });
	});

	it('reports a failed transition through retry_automation_work_item and counts it as retried', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advanceError: true
		});

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({ claimed: 1, retried: 1, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith(
			'retry_automation_work_item',
			expect.objectContaining({
				p_work_item_id: 'a',
				p_claim_token: 'claim-a',
				p_error_code: 'advance_failed',
				p_error_message: 'db exploded',
				p_permanent: false
			})
		);
	});

	it('surfaces an error when even recording the step failure fails', async () => {
		const { client } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advanceError: true,
			retryError: 'ledger unreachable'
		});

		await expect(drainAutomationWork({ client, now: () => 0 })).rejects.toThrow(
			/record an automation step failure/
		);
	});

	it('tallies each transition outcome into the right bucket and ignores lost claims', async () => {
		const outcomes: Record<string, string> = {
			a: 'waiting',
			b: 'completed',
			c: 'action_not_available',
			d: 'enrollment_expired',
			e: 'claim_lost',
			f: 'paused_customer_reply'
		};
		const { client } = workClient({
			intake: [0],
			claims: [[item('a'), item('b'), item('c'), item('d'), item('e'), item('f')]],
			advance: (id) => outcomes[id]
		});

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({
			claimed: 6,
			waited: 1,
			completed: 1,
			parked: 2,
			cancelled: 1,
			stoppedBy: 'idle'
		});
	});

	it('runs an email action effect with the minted link and counts a send', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_email',
			perform: () => 'action_sent'
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({ claimed: 1, sent: 1, completed: 0, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith(
			'perform_automation_email_effect',
			expect.objectContaining({
				p_work_item_id: 'a',
				p_claim_token: 'claim-a',
				p_quote_url: 'https://app.example.com/q/token',
				p_quote_token_hash: '\\xdeadbeef'
			})
		);
	});

	it('runs an sms action effect with no minted link and counts a send', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_sms',
			performSms: () => 'action_sent'
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({ claimed: 1, sent: 1, completed: 0, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith(
			'perform_automation_sms_effect',
			expect.objectContaining({ p_work_item_id: 'a', p_claim_token: 'claim-a' })
		);
		// No link minted for a text: the sms effect call never carries a quote URL/token.
		const smsCall = rpc.mock.calls.find(([name]) => name === 'perform_automation_sms_effect');
		expect(smsCall?.[1]).not.toHaveProperty('p_quote_url');
	});

	it('runs a website inquiry customer message effect and counts a send', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_customer_message',
			performMessage: () => 'action_sent'
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({ claimed: 1, sent: 1, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith('perform_automation_inquiry_message_effect', {
			p_work_item_id: 'a',
			p_claim_token: 'claim-a'
		});
	});

	it('writes a job review request from Review settings with its own link and counts a send', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_review_request',
			reviewDraft: {
				channel: 'sms',
				business_name: 'Raad LTD',
				customer_name: 'Sam Carter',
				customer_first_name: 'Sam',
				message_styles: null,
				request_plan: null
			},
			performReview: () => 'action_sent'
		});

		const result = await drainAutomationWork({
			client,
			now: () => 0,
			createQuoteLink: stubLink,
			reviewLinkOrigin: () => 'https://app.example.com'
		});

		expect(result).toMatchObject({ claimed: 1, sent: 1, stoppedBy: 'idle' });
		const call = rpc.mock.calls.find(
			([name]) => name === 'perform_automation_review_request_effect'
		);
		const args = call?.[1] as Record<string, unknown>;
		expect(args).toMatchObject({ p_work_item_id: 'a', p_claim_token: 'claim-a', p_subject: '' });
		expect(String(args.p_link_url)).toMatch(/^https:\/\/app\.example\.com\//);
		// The text carries the business and the customer's link, not a raw {{placeholder}}.
		expect(String(args.p_body_text)).toContain(String(args.p_link_url));
		expect(String(args.p_body_text)).not.toContain('{{');
	});

	it('does not run the review request effect when the draft finds the claim gone', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_review_request',
			reviewDraft: null
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({ claimed: 1, sent: 0, cancelled: 0, retried: 0 });
		expect(rpc).not.toHaveBeenCalledWith(
			'perform_automation_review_request_effect',
			expect.anything()
		);
	});

	it('drains due email fallbacks after intake and before claiming work', async () => {
		const { client, rpc } = workClient({ intake: [0], claims: [], fallbacks: 3 });

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result.fallbacks).toBe(3);
		const order = rpc.mock.calls.map(([name]) => name);
		expect(order.indexOf('intake_automation_events')).toBeLessThan(
			order.indexOf('process_automation_sms_email_fallbacks')
		);
		expect(order.indexOf('process_automation_sms_email_fallbacks')).toBeLessThan(
			order.indexOf('claim_automation_work_items')
		);
	});

	it('maps a permanent skip to cancelled and a temporary skip to retried', async () => {
		const outcomes: Record<string, string> = { a: 'action_cancelled', b: 'action_deferred' };
		const { client } = workClient({
			intake: [0],
			claims: [[item('a'), item('b')]],
			advance: () => 'action_due_email',
			perform: (id) => outcomes[id]
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({
			claimed: 2,
			sent: 0,
			cancelled: 1,
			retried: 1,
			stoppedBy: 'idle'
		});
	});

	it('maps a permanent sms skip to cancelled and a temporary sms skip to retried', async () => {
		const outcomes: Record<string, string> = { a: 'action_cancelled', b: 'action_deferred' };
		const { client } = workClient({
			intake: [0],
			claims: [[item('a'), item('b')]],
			advance: () => 'action_due_sms',
			performSms: (id) => outcomes[id]
		});

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({
			claimed: 2,
			sent: 0,
			cancelled: 1,
			retried: 1,
			stoppedBy: 'idle'
		});
	});

	it('does not count an action whose claim was lost', async () => {
		const { client } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_email',
			perform: () => 'claim_lost'
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({
			claimed: 1,
			sent: 0,
			cancelled: 0,
			retried: 0,
			fallbacks: 0,
			stoppedBy: 'idle'
		});
	});

	it('backs the row off through retry when the effect itself fails', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_email',
			performError: true
		});

		const result = await drainAutomationWork({ client, now: () => 0, createQuoteLink: stubLink });

		expect(result).toMatchObject({ claimed: 1, sent: 0, retried: 1, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith(
			'retry_automation_work_item',
			expect.objectContaining({
				p_work_item_id: 'a',
				p_error_code: 'advance_failed',
				p_error_message: 'send path exploded',
				p_permanent: false
			})
		);
	});

	it('backs the row off through retry when the sms effect itself fails', async () => {
		const { client, rpc } = workClient({
			intake: [0],
			claims: [[item('a')]],
			advance: () => 'action_due_sms',
			performSmsError: true
		});

		const result = await drainAutomationWork({ client, now: () => 0 });

		expect(result).toMatchObject({ claimed: 1, sent: 0, retried: 1, stoppedBy: 'idle' });
		expect(rpc).toHaveBeenCalledWith(
			'retry_automation_work_item',
			expect.objectContaining({
				p_work_item_id: 'a',
				p_error_code: 'advance_failed',
				p_error_message: 'sms path exploded',
				p_permanent: false
			})
		);
	});

	it('throws when the claim RPC itself errors', async () => {
		const { client } = workClient({ intake: [0], claimError: 'deadlock detected' });

		await expect(drainAutomationWork({ client, now: () => 0 })).rejects.toThrow(
			/Could not claim automation work/
		);
	});
});

describe('drainAutomationEvents', () => {
	it('drains full intake batches in order and stops on the first short batch', async () => {
		const { client, rpc } = workClient({ intake: [50, 50, 10] });

		const processed = await drainAutomationEvents(
			client,
			{ intakeBatchSize: 50 },
			Number.MAX_SAFE_INTEGER,
			() => 0
		);

		expect(processed).toBe(110);
		expect(rpc.mock.calls.filter(([name]) => name === 'intake_automation_events')).toHaveLength(3);
	});

	it('never runs more than the intake batch ceiling', async () => {
		const { client, rpc } = workClient({ intake: [50, 50, 50, 50] });

		const processed = await drainAutomationEvents(
			client,
			{ intakeBatchSize: 50, maxIntakeBatches: 2 },
			Number.MAX_SAFE_INTEGER,
			() => 0
		);

		expect(processed).toBe(100);
		expect(rpc.mock.calls.filter(([name]) => name === 'intake_automation_events')).toHaveLength(2);
	});

	it('takes in nothing once the deadline has already passed', async () => {
		const { client, rpc } = workClient({ intake: [50] });

		const processed = await drainAutomationEvents(client, {}, 0, () => 5);

		expect(processed).toBe(0);
		expect(rpc.mock.calls.some(([name]) => name === 'intake_automation_events')).toBe(false);
	});

	it('throws when the intake RPC errors', async () => {
		const rpc = vi.fn(async () => ({ data: null, error: { message: 'intake blew up' } }));
		const client = { rpc } as AutomationWorkerClient;

		await expect(
			drainAutomationEvents(client, {}, Number.MAX_SAFE_INTEGER, () => 0)
		).rejects.toThrow(/take in automation events/);
	});
});

describe('runMonitoredAutomationWake', () => {
	const wake = { wakeCorrelationId: 'wake-1', nowIso: () => '2026-09-13T00:00:00.000Z' };

	it('records the drain outcome with its counts and returns them', async () => {
		const { client, rpc } = workClient({ intake: [0], claims: [[item('a')]] });

		const result = await runMonitoredAutomationWake({ client, ...wake, now: () => 0 });

		expect(result).toMatchObject({ outcome: 'idle', claimed: 1, completed: 1 });
		expect(rpc).toHaveBeenCalledWith(
			'record_automation_worker_wake_result',
			expect.objectContaining({
				p_worker_name: AUTOMATION_WORKER_NAME,
				p_wake_correlation_id: 'wake-1',
				p_route_outcome: 'idle',
				p_claimed: 1,
				p_completed: 1
			})
		);
	});

	it('reports route_deadline when the drain overruns the whole-route deadline', async () => {
		const { client, rpc } = workClient({ intake: [0], claimDelayMs: 60 });

		const result = await runMonitoredAutomationWake({ client, ...wake, routeDeadlineMs: 5 });

		expect(result).toEqual({ outcome: 'route_deadline' });
		expect(rpc).toHaveBeenCalledWith(
			'record_automation_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'route_deadline' })
		);
	});

	it('still returns the drain outcome when the ledger write fails', async () => {
		const { client } = workClient({ intake: [0], claims: [], recordError: true });
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

		const result = await runMonitoredAutomationWake({ client, ...wake, now: () => 0 });

		expect(result).toMatchObject({ outcome: 'idle' });
		consoleError.mockRestore();
	});

	it('records an error outcome and rethrows when the drain fails', async () => {
		const { client, rpc } = workClient({ intake: [0], claimError: 'deadlock detected' });

		await expect(runMonitoredAutomationWake({ client, ...wake, now: () => 0 })).rejects.toThrow(
			/Could not claim automation work/
		);
		expect(rpc).toHaveBeenCalledWith(
			'record_automation_worker_wake_result',
			expect.objectContaining({ p_route_outcome: 'error' })
		);
	});
});
