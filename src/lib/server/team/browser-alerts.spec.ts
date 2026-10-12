import { describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

import {
	buildBrowserAlertPayload,
	drainBrowserAlerts,
	pushOutcomeFor,
	vapidKeys
} from './browser-alerts';
import type { InquiryAlertClient } from './inquiry-alerts';
import { teamNotificationHref } from '$lib/team/notifications';

function delivery(id: string, overrides: Record<string, unknown> = {}) {
	return {
		notification_id: `n-${id}`,
		subscription_id: `s-${id}`,
		claim_token: `token-${id}`,
		endpoint: `https://push.example.test/${id}`,
		p256dh: 'key',
		auth_secret: 'auth',
		organization_id: 'org-1',
		organization_name: 'Raad & Sons',
		kind: 'schedule.assigned',
		subject_type: 'job',
		subject_id: `job-${id}`,
		title: "You're on Smith: Spring cleanup, Tue 14 Oct, 9:00 am",
		body: null,
		attempts: 0,
		...overrides
	};
}

// Claims come out in order; settle answers what the database would for each outcome.
function scriptedClient(batches: unknown[][]) {
	const settles: Array<Record<string, unknown>> = [];
	const client: InquiryAlertClient = {
		rpc: vi.fn(async (name: string, args?: Record<string, unknown>) => {
			if (name === 'claim_push_deliveries') return { data: batches.shift() ?? [], error: null };
			if (name === 'team_notification_links') return { data: [], error: null };
			if (name === 'settle_push_delivery') {
				settles.push(args ?? {});
				return { data: args?.p_outcome, error: null };
			}
			throw new Error(`unexpected rpc ${name}`);
		})
	};
	return { client, settles };
}

describe('pushOutcomeFor', () => {
	it('treats a browser that says the computer is gone as gone', () => {
		expect(pushOutcomeFor({ statusCode: 410 })).toBe('gone');
		expect(pushOutcomeFor({ statusCode: 404 })).toBe('gone');
	});

	it('does not retry what a retry cannot fix', () => {
		expect(pushOutcomeFor({ statusCode: 403 })).toBe('failed');
		expect(pushOutcomeFor({ statusCode: 413 })).toBe('failed');
	});

	it('retries busy services and network faults', () => {
		expect(pushOutcomeFor({ statusCode: 429 })).toBe('retry');
		expect(pushOutcomeFor({ statusCode: 503 })).toBe('retry');
		expect(pushOutcomeFor(new Error('socket hang up'))).toBe('retry');
	});
});

describe('buildBrowserAlertPayload', () => {
	it('carries the alert, where it opens, and a tag so the same alert never shows twice', () => {
		const payload = buildBrowserAlertPayload(delivery('1'), '/jobs/job-1');
		expect(payload).toEqual({
			title: "You're on Smith: Spring cleanup, Tue 14 Oct, 9:00 am",
			body: 'Raad & Sons',
			url: '/jobs/job-1',
			tag: 'n-1'
		});
		expect(buildBrowserAlertPayload(delivery('1', { body: 'Details' }), '/x').body).toBe('Details');
	});
});

describe('vapidKeys', () => {
	it('is null while the keys are not configured', () => {
		expect(vapidKeys()).toBeNull();
	});
});

describe('where the new alerts open', () => {
	it('opens a Visit alert on its Job and a timer alert on Timesheets', () => {
		expect(teamNotificationHref(undefined, 'job', 'job-1')).toBe('/jobs/job-1');
		expect(teamNotificationHref(undefined, 'running_timer', 't')).toBe('/timesheets');
	});

	it('opens an Assessment alert on its Request', () => {
		const link = {
			subject_type: 'assessment',
			subject_id: 'a1',
			request_id: 'r1',
			job_id: null,
			client_id: null
		};
		expect(teamNotificationHref(link, 'assessment', 'a1')).toBe('/requests/r1');
	});

	it('opens a customer message on its conversation', () => {
		const link = {
			subject_type: 'inbound_message',
			subject_id: 'm1',
			request_id: null,
			job_id: null,
			client_id: 'c1'
		};
		expect(teamNotificationHref(link, 'inbound_message', 'm1')).toBe('/communications?client=c1');
		expect(teamNotificationHref(undefined, 'inbound_message', 'm1')).toBe('/communications');
	});
});

describe('drainBrowserAlerts', () => {
	it('sends each computer on its own and settles each by what happened', async () => {
		const { client, settles } = scriptedClient([[delivery('a'), delivery('b'), delivery('c')]]);
		const send = vi.fn(async (target: { endpoint: string }) => {
			if (target.endpoint.endsWith('/b'))
				throw Object.assign(new Error('Gone'), { statusCode: 410 });
			if (target.endpoint.endsWith('/c'))
				throw Object.assign(new Error('Busy'), { statusCode: 503 });
		});

		const result = await drainBrowserAlerts({ client, send, batchSize: 50 });

		expect(result).toEqual({ sent: 1, retried: 1, failed: 0, gone: 1 });
		expect(settles.map((settle) => settle.p_outcome)).toEqual(['sent', 'gone', 'retry']);
		expect(settles[1]).toMatchObject({ p_subscription_id: 's-b', p_claim_token: 'token-b' });
		expect(settles[2].p_error).toBe('Busy');
	});

	it('sends the path the alert opens', async () => {
		const { client } = scriptedClient([[delivery('a')]]);
		const send = vi.fn(async () => undefined);
		await drainBrowserAlerts({ client, send });
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({ endpoint: 'https://push.example.test/a' }),
			expect.objectContaining({ url: '/jobs/job-a', tag: 'n-a' })
		);
	});

	it('claims nothing at all while the server has no keys', async () => {
		const { client } = scriptedClient([[delivery('a')]]);
		const result = await drainBrowserAlerts({ client });
		expect(result).toEqual({ sent: 0, retried: 0, failed: 0, gone: 0 });
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('stops starting new sends after its time budget', async () => {
		const { client, settles } = scriptedClient([[delivery('a'), delivery('b')]]);
		let clock = 0;
		const send = vi.fn(async () => {
			clock += 30_000;
		});
		const result = await drainBrowserAlerts({
			client,
			send,
			timeBudgetMs: 20_000,
			now: () => clock
		});
		expect(send).toHaveBeenCalledTimes(1);
		expect(settles).toHaveLength(1);
		expect(result.sent).toBe(1);
	});
});
