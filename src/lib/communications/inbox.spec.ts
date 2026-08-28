import { describe, expect, it } from 'vitest';
import {
	groupMessagesByContact,
	type InboundInboxMessage,
	type OutboundInboxMessage
} from './inbox';

function outbound(overrides: Partial<OutboundInboxMessage> = {}): OutboundInboxMessage {
	return {
		direction: 'outbound',
		id: 'out-1',
		client_id: 'client-1',
		client_name: 'Alice',
		client_email: 'alice@example.test',
		quote_id: null,
		subject: 'Quote ready',
		text_content: 'Here it is.',
		status: 'submitted',
		failure_message: null,
		delivery_outcome: null,
		delivery_outcome_at: null,
		created_at: '2026-08-25T10:00:00.000Z',
		resent_from_intent_id: null,
		resent_into_intent_id: null,
		attachments: [],
		can_resend: false,
		send_kind: 'manual',
		created_by_name: 'Jafar',
		assigned_to: null,
		assigned_to_name: null,
		is_following: false,
		...overrides
	};
}

function inbound(overrides: Partial<InboundInboxMessage> = {}): InboundInboxMessage {
	return {
		direction: 'inbound',
		id: 'in-1',
		client_id: 'client-1',
		client_name: 'Alice',
		sender_email: 'alice@example.test',
		sender_name: 'Alice',
		subject: 'Re: Quote ready',
		text_content: 'Looks good.',
		created_at: '2026-08-25T11:00:00.000Z',
		in_reply_to_intent_id: 'out-1',
		message_kind: 'reply',
		review_status: 'accepted',
		review_reason: null,
		automation_suppressed: false,
		attachment_count: 0,
		attachments: [],
		unread: true,
		provider: 'brevo',
		provider_message_id: 'prov-1',
		assigned_to: null,
		assigned_to_name: null,
		is_following: false,
		...overrides
	};
}

describe('groupMessagesByContact', () => {
	it('groups a known contact into one row spanning both directions', () => {
		const groups = groupMessagesByContact([
			inbound({ id: 'in-1', created_at: '2026-08-25T11:00:00.000Z' }),
			outbound({ id: 'out-1', created_at: '2026-08-25T10:00:00.000Z' })
		]);
		expect(groups).toHaveLength(1);
		expect(groups[0].key).toBe('client-1');
		expect(groups[0].latest.id).toBe('in-1');
		expect(groups[0].unreadCount).toBe(1);
		// Oldest first for the timeline, regardless of the page's descending input order.
		expect(groups[0].messages.map((m) => m.id)).toEqual(['out-1', 'in-1']);
	});

	it('keeps two unresolved senders in separate rows instead of one bucket', () => {
		const groups = groupMessagesByContact([
			inbound({ id: 'in-a', client_id: null, client_name: null, sender_email: 'a@unknown.test' }),
			inbound({ id: 'in-b', client_id: null, client_name: null, sender_email: 'b@unknown.test' })
		]);
		expect(groups).toHaveLength(2);
		expect(groups.map((g) => g.key).sort()).toEqual([
			'guarded:a@unknown.test',
			'guarded:b@unknown.test'
		]);
		expect(groups.every((g) => g.guarded)).toBe(true);
		expect(groups.every((g) => g.clientId === null)).toBe(true);
	});

	it('collapses repeated guarded messages from the same unknown sender into one row', () => {
		const groups = groupMessagesByContact([
			inbound({
				id: 'in-a2',
				client_id: null,
				client_name: null,
				sender_email: 'a@unknown.test',
				created_at: '2026-08-25T12:00:00.000Z'
			}),
			inbound({
				id: 'in-a1',
				client_id: null,
				client_name: null,
				sender_email: 'a@unknown.test',
				created_at: '2026-08-25T09:00:00.000Z'
			})
		]);
		expect(groups).toHaveLength(1);
		expect(groups[0].messages.map((m) => m.id)).toEqual(['in-a1', 'in-a2']);
		expect(groups[0].unreadCount).toBe(2);
	});

	it('does not count a read inbound message toward the unread total', () => {
		const groups = groupMessagesByContact([inbound({ unread: false })]);
		expect(groups[0].unreadCount).toBe(0);
	});

	it('carries assignment and follow state onto the group, constant across every message in it', () => {
		const groups = groupMessagesByContact([
			inbound({ id: 'in-1', assigned_to: 'user-9', assigned_to_name: 'Robin', is_following: true }),
			outbound({ id: 'out-1' })
		]);
		expect(groups[0].assignedTo).toBe('user-9');
		expect(groups[0].assignedToName).toBe('Robin');
		expect(groups[0].isFollowing).toBe(true);
	});

	it('falls back to sender_name then sender_email for a guarded row heading', () => {
		const named = groupMessagesByContact([
			inbound({
				client_id: null,
				client_name: null,
				sender_name: 'Bob',
				sender_email: 'bob@unknown.test'
			})
		]);
		expect(named[0].name).toBe('Bob');

		const anonymous = groupMessagesByContact([
			inbound({
				client_id: null,
				client_name: null,
				sender_name: null,
				sender_email: 'x@unknown.test'
			})
		]);
		expect(anonymous[0].name).toBe('x@unknown.test');
	});
});
