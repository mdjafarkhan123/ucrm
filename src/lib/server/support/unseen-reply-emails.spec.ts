import { beforeEach, describe, expect, it, vi } from 'vitest';

const enqueueEmailDelivery = vi.fn();
vi.mock('$lib/server/events/dispatcher', () => ({
	enqueueEmailDelivery: (...args: unknown[]) => enqueueEmailDelivery(...args)
}));
vi.mock('$lib/server/jafar/owner-settings', () => ({
	getOrCreateOwnerSettings: vi.fn().mockResolvedValue({
		alert_recipient_emails: ['jafar@example.com', 'ops@example.com']
	})
}));

const { buildMemberEmail, buildUpliftEmail, sendDueSupportUnseenReplyEmails } =
	await import('./unseen-reply-emails');
type DueUnseenReply = Parameters<typeof buildMemberEmail>[0];

// The database picks who is due and silences a chat after one email (checked against the real database);
// this checks the emails say the right thing and that a reminder is stamped only once its email is queued.
const ORIGIN = 'https://app.example.com';

function reminder(overrides: Partial<DueUnseenReply> = {}): DueUnseenReply {
	return {
		id: 'rem-1',
		thread_id: 'thread-1',
		organization_id: 'org-1',
		organization_name: 'Bright Spark',
		recipient_user_id: 'user-1',
		recipient_email: 'sam@example.com',
		recipient_name: 'Sam Rivera',
		started_by_name: 'Sam Rivera',
		topic: 'website',
		first_unseen_at: '2026-10-03T03:21:08.954676+00:00',
		unseen_count: 1,
		messages: [
			{
				sender_name: 'Uplift Support · Jafar',
				body: 'Your site is <ready>',
				attachment_count: 2,
				created_at: '2026-10-03T03:21:08.954676+00:00'
			}
		],
		...overrides
	};
}

function client(due: DueUnseenReply[], existingKeys: string[] = []) {
	const rpc = vi.fn(async (name: string) =>
		name === 'due_support_unseen_reply_emails'
			? { data: due, error: null }
			: { data: null, error: null }
	);
	const from = vi.fn(() => {
		let key = '';
		const chain = {
			select: () => chain,
			eq: (_column: string, value: string) => {
				key = value;
				return chain;
			},
			maybeSingle: async () => ({
				data: existingKeys.includes(key) ? { id: 'out-1' } : null,
				error: null
			})
		};
		return chain;
	});
	return { rpc, from } as never as Parameters<typeof sendDueSupportUnseenReplyEmails>[0] & {
		rpc: typeof rpc;
	};
}

function stamped(db: { rpc: ReturnType<typeof vi.fn> }) {
	return db.rpc.mock.calls.filter(([name]) => name === 'mark_support_unseen_reply_emailed');
}

beforeEach(() => {
	enqueueEmailDelivery.mockReset();
	enqueueEmailDelivery.mockResolvedValue('out-1');
});

describe('buildMemberEmail', () => {
	it('shows the reply safely, notes the files, and links straight to the chat', () => {
		const email = buildMemberEmail(reminder(), ORIGIN);
		expect(email.subject).toBe('Uplift Support replied to your chat');
		expect(email.htmlContent).toContain('Hi Sam, Uplift Support sent a reply in your Website chat');
		expect(email.htmlContent).toContain('Your site is &lt;ready&gt;');
		expect(email.htmlContent).not.toContain('<ready>');
		expect(email.htmlContent).toContain('Sent 2 files — open the chat to see them.');
		expect(email.htmlContent).toContain(`href="${ORIGIN}/dashboard?support_chat=thread-1"`);
		expect(email.textContent).toContain(
			'Replies to this email are not read — answer in the chat instead.'
		);
		expect(email.textContent).toContain(
			'We will not email you again about this chat until you open it.'
		);
	});

	it('counts the replies it does not show', () => {
		const email = buildMemberEmail(reminder({ unseen_count: 7 }), ORIGIN);
		expect(email.subject).toBe('Uplift Support sent 7 replies in your chat');
		expect(email.textContent).toContain('…and 6 earlier messages in the chat.');
	});

	it('greets someone with no name on file without showing their address', () => {
		const email = buildMemberEmail(reminder({ recipient_name: 'sam@example.com' }), ORIGIN);
		expect(email.textContent.startsWith('Hi there,')).toBe(true);
	});
});

describe('buildUpliftEmail', () => {
	it('names the business and links to the chat in the Support Inbox', () => {
		const email = buildUpliftEmail(
			reminder({
				recipient_user_id: null,
				recipient_email: null,
				messages: [{ ...reminder().messages[0], sender_name: 'Sam Rivera', attachment_count: 0 }]
			}),
			ORIGIN
		);
		expect(email.subject).toBe('Bright Spark: 1 message waiting in Support');
		expect(email.htmlContent).toContain(`href="${ORIGIN}/jafar/support?thread=thread-1"`);
		expect(email.textContent).toContain('last from Sam Rivera');
	});
});

describe('sendDueSupportUnseenReplyEmails', () => {
	it('queues one email per member and stamps the reminder for that stretch', async () => {
		const db = client([reminder()]);
		expect(await sendDueSupportUnseenReplyEmails(db, { origin: ORIGIN })).toBe(1);
		expect(enqueueEmailDelivery).toHaveBeenCalledTimes(1);
		expect(enqueueEmailDelivery.mock.calls[0][1]).toMatchObject({
			recipientEmail: 'sam@example.com',
			idempotencyKey: 'support-unseen:rem-1:2026-10-03T03:21:08.954676+00:00',
			target: { targetKind: 'organization', targetId: 'org-1' }
		});
		expect(stamped(db)[0][1]).toEqual({
			reminder_id: 'rem-1',
			reminder_first_unseen_at: '2026-10-03T03:21:08.954676+00:00'
		});
	});

	it('sends Uplift a copy at every alert address', async () => {
		const db = client([reminder({ recipient_user_id: null, recipient_email: null })]);
		await sendDueSupportUnseenReplyEmails(db, { origin: ORIGIN });
		expect(enqueueEmailDelivery.mock.calls.map(([, email]) => email.recipientEmail)).toEqual([
			'jafar@example.com',
			'ops@example.com'
		]);
		expect(stamped(db)).toHaveLength(1);
	});

	it('leaves a reminder due when its email never reached the outbox', async () => {
		enqueueEmailDelivery.mockRejectedValue(new Error('database down'));
		const db = client([reminder()]);
		expect(await sendDueSupportUnseenReplyEmails(db, { origin: ORIGIN })).toBe(0);
		expect(stamped(db)).toHaveLength(0);
	});

	it('stamps a reminder whose email is queued but failed to send, leaving the retry to the outbox', async () => {
		enqueueEmailDelivery.mockRejectedValue(new Error('provider down'));
		const db = client([reminder()], ['support-unseen:rem-1:2026-10-03T03:21:08.954676+00:00']);
		expect(await sendDueSupportUnseenReplyEmails(db, { origin: ORIGIN })).toBe(1);
		expect(stamped(db)).toHaveLength(1);
	});
});
