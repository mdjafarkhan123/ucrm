import { describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

import { DEFAULT_REVIEW_REQUEST_PLAN, newReviewReminder } from '$lib/reviews/settings';
import {
	drainReviewReminders,
	writeReviewReminder,
	type ClaimedReviewReminder,
	type ReviewReminderClient
} from './reminders';

const mint = () => ({ token: 'T'.repeat(43), tokenHash: '\\xabc' });

function claimed(overrides: Partial<ClaimedReviewReminder> = {}): ClaimedReviewReminder {
	return {
		request_id: 'req-1',
		claim_token: 'claim-1',
		organization_id: 'org-1',
		slot: 1,
		channel: 'sms',
		style: 'short',
		business_name: 'Raad LTD',
		customer_first_name: 'Sam',
		customer_name: 'Sam Lee',
		request_plan: null,
		...overrides
	};
}

describe('writeReviewReminder', () => {
	it('writes the first reminder from the ready-made plan with its own link and the next wait', () => {
		const args = writeReviewReminder(claimed(), 'https://app.example.com', mint);

		expect(args.p_wait_days).toBe(3);
		expect(args.p_next_wait_days).toBe(2);
		expect(args.p_body_text).toBe(
			`A quick reminder from Raad LTD: how did we do? https://app.example.com/v/${'T'.repeat(43)}`
		);
		expect(args.p_body_html).toBe('');
		expect(args.p_token_hash).toBe('\\xabc');
	});

	it('says there is no next reminder on the last one', () => {
		const args = writeReviewReminder(claimed({ slot: 2 }), 'https://app.example.com', mint);
		expect(args.p_wait_days).toBe(2);
		expect(args.p_next_wait_days).toBeNull();
	});

	it('writes an email reminder with a subject and a clickable link', () => {
		const args = writeReviewReminder(
			claimed({ channel: 'email', style: 'friendly' }),
			'https://app.example.com',
			mint
		);
		expect(args.p_subject).toBe('A quick reminder from Raad LTD');
		expect(args.p_body_text).toContain('Hi Sam,');
		expect(args.p_body_html).toContain(`<a href="https://app.example.com/v/${'T'.repeat(43)}">`);
	});

	it('uses the saved plan, and sends a null body when the plan no longer has this reminder', () => {
		const plan = {
			...DEFAULT_REVIEW_REQUEST_PLAN,
			reminders: [newReviewReminder('0d3c7a52-4b1e-4f3a-9a61-7e2b8c5d1f09', 7)]
		};
		expect(
			writeReviewReminder(claimed({ request_plan: plan }), 'https://a.example', mint).p_wait_days
		).toBe(7);
		const gone = writeReviewReminder(claimed({ slot: 2, request_plan: plan }), 'https://a.example');
		expect(gone.p_body_text).toBeNull();
		expect(gone.p_link_url).toBeNull();
	});
});

describe('drainReviewReminders', () => {
	it('claims until idle, counts each outcome, and keeps going past a failed send', async () => {
		const batches = [
			[claimed(), claimed({ request_id: 'req-2' }), claimed({ request_id: 'req-3' })]
		];
		const outcomes: Record<string, { data: unknown; error: { message: string } | null }> = {
			'req-1': { data: 'sent', error: null },
			'req-2': { data: null, error: { message: 'db exploded' } },
			'req-3': { data: 'stopped', error: null }
		};
		const rpc = vi.fn(async (name: string, args?: Record<string, unknown>) => {
			if (name === 'claim_review_reminders') return { data: batches.shift() ?? [], error: null };
			return outcomes[String(args?.p_request_id)];
		});
		const errorLog = vi.spyOn(console, 'error').mockImplementation(() => {});

		const counts = await drainReviewReminders(
			{ rpc } as ReviewReminderClient,
			Number.POSITIVE_INFINITY,
			() => 0,
			() => 'https://app.example.com'
		);

		expect(counts).toEqual({ claimed: 3, sent: 1, waiting: 0, stopped: 1 });
		expect(rpc.mock.calls.filter(([name]) => name === 'claim_review_reminders')).toHaveLength(2);
		expect(errorLog).toHaveBeenCalledOnce();
		errorLog.mockRestore();
	});

	it('does not claim when the deadline has passed', async () => {
		const rpc = vi.fn();
		const counts = await drainReviewReminders({ rpc } as ReviewReminderClient, 0, () => 1);
		expect(counts.claimed).toBe(0);
		expect(rpc).not.toHaveBeenCalled();
	});
});
