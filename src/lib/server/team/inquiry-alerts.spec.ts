import { describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: {} }));
vi.mock('$lib/server/email/brevo', () => ({ sendTransactionalEmail: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

import {
	buildAlertEmail,
	drainTeamAlertEmails,
	type AlertEmail,
	type InquiryAlertClient
} from './inquiry-alerts';
import { teamNotificationHref } from '$lib/team/notifications';

function claimed(id: string, overrides: Record<string, unknown> = {}) {
	return {
		notification_id: id,
		claim_token: `token-${id}`,
		organization_id: 'org-1',
		organization_name: 'Raad & Sons',
		recipient_email: `${id}@example.test`,
		kind: 'website_inquiry.received',
		subject_type: 'form_submission',
		subject_id: `submission-${id}`,
		title: 'New website inquiry from <Jamie>',
		body: 'Sent the Get a quote form.',
		attempts: 0,
		...overrides
	};
}

// Claims come out in order; settle answers what the database would for a sent or failed email.
function scriptedClient(batches: unknown[][]) {
	const settles: Array<Record<string, unknown>> = [];
	const client: InquiryAlertClient = {
		rpc: vi.fn(async (name: string, args?: Record<string, unknown>) => {
			if (name === 'claim_team_notification_emails')
				return { data: batches.shift() ?? [], error: null };
			if (name === 'team_notification_links')
				return {
					data: [
						{
							subject_type: 'form_submission',
							subject_id: (args?.p_subject_ids as string[])[0],
							request_id: 'request-9',
							job_id: null,
							client_id: 'client-9'
						}
					],
					error: null
				};
			if (name === 'settle_team_notification_email') {
				settles.push(args ?? {});
				return { data: args?.p_sent ? 'sent' : 'retry', error: null };
			}
			throw new Error(`unexpected rpc ${name}`);
		})
	};
	return { client, settles };
}

describe('teamNotificationHref', () => {
	it('opens the request a form became, then its job, then its client', () => {
		const base = {
			subject_type: 'form_submission',
			subject_id: 's',
			request_id: null,
			job_id: null,
			client_id: null
		};
		expect(teamNotificationHref({ ...base, request_id: 'r' }, 'form_submission', 's')).toBe(
			'/requests/r'
		);
		expect(
			teamNotificationHref({ ...base, job_id: 'j', client_id: 'c' }, 'form_submission', 's')
		).toBe('/jobs/j');
		expect(teamNotificationHref({ ...base, client_id: 'c' }, 'form_submission', 's')).toBe(
			'/clients/c'
		);
		expect(teamNotificationHref(undefined, 'form_submission', 's')).toBe('/requests');
	});

	it('opens a chat by its client once matched, otherwise by the chat itself', () => {
		const link = {
			subject_type: 'website_chat_session',
			subject_id: 's1',
			request_id: null,
			job_id: null,
			client_id: 'c1'
		};
		expect(teamNotificationHref(link, 'website_chat_session', 's1')).toBe(
			'/communications?client=c1'
		);
		expect(teamNotificationHref({ ...link, client_id: null }, 'website_chat_session', 's1')).toBe(
			'/communications?client=webchat%3As1'
		);
	});
});

describe('buildAlertEmail', () => {
	it('escapes names in the HTML and keeps plain text readable', () => {
		const email = buildAlertEmail(claimed('a'), 'https://app.test/requests/r');
		expect(email.to).toEqual({ email: 'a@example.test' });
		expect(email.subject).toBe('New website inquiry from <Jamie> · Raad & Sons');
		expect(email.htmlContent).toContain('&lt;Jamie&gt;');
		expect(email.htmlContent).not.toContain('<Jamie>');
		expect(email.textContent).toContain('Open it in your CRM: https://app.test/requests/r');
	});

	it('tells a Task assignee why they got it, not that they were chosen for inquiries', () => {
		const email = buildAlertEmail(
			claimed('a', {
				kind: 'pipeline.task_assigned',
				subject_type: 'opportunity',
				title: 'Sara gave you a Task: Call back'
			}),
			'https://app.test/pipeline?brief=o1'
		);
		expect(email.textContent).toContain('a teammate at Raad & Sons gave you a Task');
		expect(email.textContent).not.toContain('website inquiries');
	});
});

describe('buildAlertEmail for quote answers', () => {
	it.each(['quote.customer_approved', 'quote.changes_requested'])(
		'tells the %s recipient why they got it and links the quote',
		(kind) => {
			const email = buildAlertEmail(
				claimed('a', {
					kind,
					subject_type: 'quote',
					title: 'Jamie approved quote #12',
					body: 'Signed by Jamie.'
				}),
				'https://app.test/quotes/q1'
			);
			expect(email.subject).toBe('Jamie approved quote #12 · Raad & Sons');
			expect(email.textContent).toContain('you look after this quote at Raad & Sons');
			expect(email.textContent).toContain('Open it in your CRM: https://app.test/quotes/q1');
			expect(email.textContent).not.toContain('website inquiries');
		}
	);

	it('opens the quote itself', () => {
		expect(teamNotificationHref(undefined, 'quote', 'q1')).toBe('/quotes/q1');
	});
});

describe('teamNotificationHref for Tasks', () => {
	it("opens one Task's card Brief, and a bulk Task's board", () => {
		expect(teamNotificationHref(undefined, 'opportunity', 'o1')).toBe('/pipeline?brief=o1');
		expect(teamNotificationHref(undefined, 'task_batch', 't1')).toBe('/pipeline');
	});
});

describe('drainTeamAlertEmails', () => {
	it('sends each claimed alert with a link to its record and settles it as sent', async () => {
		const { client, settles } = scriptedClient([[claimed('a'), claimed('b')]]);
		const send = vi.fn<(email: AlertEmail) => Promise<void>>(async () => {});
		const result = await drainTeamAlertEmails({ client, send, origin: 'https://app.test' });

		expect(result).toEqual({ sent: 2, retried: 0, failed: 0 });
		expect(send).toHaveBeenCalledTimes(2);
		expect(send.mock.calls[0][0].textContent).toContain('https://app.test/requests/request-9');
		expect(settles.map((s) => [s.p_notification_id, s.p_claim_token, s.p_sent])).toEqual([
			['a', 'token-a', true],
			['b', 'token-b', true]
		]);
	});

	it('settles a provider failure for retry without stopping the rest of the batch', async () => {
		const { client, settles } = scriptedClient([[claimed('a'), claimed('b')]]);
		const send = vi
			.fn()
			.mockRejectedValueOnce(new Error('Brevo request failed with status 503'))
			.mockResolvedValueOnce(undefined);
		const result = await drainTeamAlertEmails({ client, send, origin: null });

		expect(result).toEqual({ sent: 1, retried: 1, failed: 0 });
		expect(settles[0]).toMatchObject({
			p_sent: false,
			p_error: 'Brevo request failed with status 503'
		});
	});

	it('claims again only while batches come back full', async () => {
		const { client } = scriptedClient([
			[claimed('a'), claimed('b')],
			[claimed('c')],
			[claimed('never')]
		]);
		const send = vi.fn<(email: AlertEmail) => Promise<void>>(async () => {});
		const result = await drainTeamAlertEmails({ client, send, origin: null, batchSize: 2 });

		expect(result.sent).toBe(3);
		expect(send).toHaveBeenCalledTimes(3);
	});

	it('starts no new email once the time budget is spent', async () => {
		const { client, settles } = scriptedClient([[claimed('a'), claimed('b')]]);
		let clock = 0;
		const send = vi.fn(async () => {
			clock += 50;
		});
		const result = await drainTeamAlertEmails({
			client,
			send,
			origin: null,
			timeBudgetMs: 40,
			now: () => clock
		});

		expect(result.sent).toBe(1);
		expect(settles).toHaveLength(1);
	});
});
