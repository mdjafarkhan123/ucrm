import { describe, expect, it } from 'vitest';
import {
	conversationCustomerPhone,
	conversationMessenger,
	formatTimeLeft,
	messageRuns,
	messengerReplyWindow,
	groupMessagesByContact,
	outboundEmailStatus,
	placeTimelineNotes,
	type InboundInboxMessage,
	type TextStopNote,
	type OutboundInboxMessage
} from './inbox';

function outbound(overrides: Partial<OutboundInboxMessage> = {}): OutboundInboxMessage {
	return {
		direction: 'outbound',
		id: 'out-1',
		client_id: 'client-1',
		channel: 'email',
		client_name: 'Alice',
		client_email: 'alice@example.test',
		client_phone: null,
		quote_id: null,
		subject: 'Quote ready',
		text_content: 'Here it is.',
		status: 'submitted',
		failure_code: null,
		failure_message: null,
		delivery_outcome: null,
		delivery_outcome_at: null,
		created_at: '2026-08-25T10:00:00.000Z',
		resent_from_intent_id: null,
		resent_into_intent_id: null,
		attachments: [],
		can_resend: false,
		scheduled_at: null,
		can_cancel_scheduled: false,
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
		channel: 'email',
		client_name: 'Alice',
		sender_email: 'alice@example.test',
		sender_phone: null,
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
		provider: 'ses',
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

	it('marks a conversation as waiting on the team when the customer spoke last, read or not', () => {
		const groups = groupMessagesByContact([
			inbound({ id: 'in-2', unread: false, created_at: '2026-08-25T12:00:00.000Z' }),
			outbound({ id: 'out-1', created_at: '2026-08-25T11:00:00.000Z' })
		]);
		expect(groups[0].unreadCount).toBe(0);
		expect(groups[0].awaitingReply).toBe(true);
	});

	it('clears waiting once a person answers, including a reply sent from the Facebook inbox', () => {
		const groups = groupMessagesByContact([
			outbound({
				id: 'out-fb',
				channel: 'messenger',
				created_by: null,
				created_at: '2026-08-25T12:00:00.000Z'
			}),
			inbound({ id: 'in-1', unread: false, created_at: '2026-08-25T11:00:00.000Z' })
		]);
		expect(groups[0].awaitingReply).toBe(false);
	});

	it('keeps waiting through automated sends and forwards, and ignores auto-responders', () => {
		const automated = groupMessagesByContact([
			outbound({ id: 'out-auto', send_kind: 'automated', created_at: '2026-08-25T13:00:00.000Z' }),
			outbound({ id: 'out-fwd', send_kind: 'forward', created_at: '2026-08-25T12:30:00.000Z' }),
			inbound({ id: 'in-1', unread: false, created_at: '2026-08-25T12:00:00.000Z' })
		]);
		expect(automated[0].awaitingReply).toBe(true);

		const autoResponder = groupMessagesByContact([
			inbound({
				id: 'in-ooo',
				unread: false,
				message_kind: 'auto_response',
				created_at: '2026-08-25T13:00:00.000Z'
			}),
			outbound({ id: 'out-1', created_at: '2026-08-25T12:00:00.000Z' })
		]);
		expect(autoResponder[0].awaitingReply).toBe(false);
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

	it("groups a known contact's inbound SMS the same way as email, by client_id", () => {
		const groups = groupMessagesByContact([
			inbound({ id: 'sms-1', channel: 'sms', sender_email: null, sender_phone: '+15551234567' }),
			outbound({ id: 'out-1' })
		]);
		expect(groups).toHaveLength(1);
		expect(groups[0].key).toBe('client-1');
	});

	it('groups an unresolved SMS sender by phone number, separately from email guarded rows', () => {
		const groups = groupMessagesByContact([
			inbound({
				id: 'sms-a',
				channel: 'sms',
				client_id: null,
				client_name: null,
				sender_email: null,
				sender_phone: '+15550000001'
			}),
			inbound({
				id: 'email-a',
				client_id: null,
				client_name: null,
				sender_email: 'a@unknown.test'
			})
		]);
		expect(groups).toHaveLength(2);
		expect(groups.map((g) => g.key).sort()).toEqual([
			'guarded-sms:+15550000001',
			'guarded:a@unknown.test'
		]);
	});

	it('falls back to sender_phone for an unresolved SMS row with no sender name', () => {
		const groups = groupMessagesByContact([
			inbound({
				channel: 'sms',
				client_id: null,
				client_name: null,
				sender_name: null,
				sender_email: null,
				sender_phone: '+15550000002'
			})
		]);
		expect(groups[0].name).toBe('+15550000002');
	});
});

describe('conversationCustomerPhone', () => {
	it('returns the phone from the most recent SMS-shaped message, oldest-first order notwithstanding', () => {
		const groups = groupMessagesByContact([
			inbound({
				id: 'sms-1',
				channel: 'sms',
				sender_email: null,
				sender_phone: '+15551110001',
				created_at: '2026-08-25T09:00:00.000Z'
			}),
			outbound({
				id: 'sms-out-1',
				channel: 'sms',
				client_email: null,
				client_phone: '+15551110002',
				created_at: '2026-08-25T11:00:00.000Z'
			})
		]);
		expect(conversationCustomerPhone(groups[0])).toBe('+15551110002');
	});

	it('returns empty when the conversation has never carried SMS activity', () => {
		const groups = groupMessagesByContact([outbound({ channel: 'email', client_phone: null })]);
		expect(conversationCustomerPhone(groups[0])).toBe('');
	});
});

describe('outboundEmailStatus', () => {
	it('reads an SMS delivery_outcome the same way it reads an email one', () => {
		const delivered = outbound({
			channel: 'sms',
			status: 'submitted',
			delivery_outcome: 'sms_delivered'
		});
		expect(outboundEmailStatus(delivered)).toEqual({ label: 'Delivered', tone: 'success' });

		const undelivered = outbound({
			channel: 'sms',
			status: 'submitted',
			delivery_outcome: 'sms_undelivered'
		});
		expect(outboundEmailStatus(undelivered)).toEqual({ label: 'Not delivered', tone: 'critical' });

		const failed = outbound({
			channel: 'sms',
			status: 'submitted',
			delivery_outcome: 'sms_failed'
		});
		expect(outboundEmailStatus(failed)).toEqual({ label: 'Failed', tone: 'critical' });

		const needsChecking = outbound({
			channel: 'sms',
			status: 'submitted',
			delivery_outcome: 'sms_needs_checking'
		});
		expect(outboundEmailStatus(needsChecking)).toEqual({
			label: 'Needs checking',
			tone: 'warning'
		});
	});

	it('still reads "Submitted" for an SMS accepted by Twilio with no status callback yet', () => {
		const submitted = outbound({ channel: 'sms', status: 'submitted', delivery_outcome: null });
		expect(outboundEmailStatus(submitted)).toEqual({ label: 'Submitted', tone: 'success' });
	});

	it('surfaces the hold reason for a queued send the worker has already looked at', () => {
		const held = outbound({
			channel: 'sms',
			status: 'queued',
			failure_message: 'This text waits for morning where the customer is before it goes out.'
		});
		expect(outboundEmailStatus(held)).toEqual({ label: 'Waiting to send', tone: 'informative' });
	});

	it('reads a freshly queued send with no hold reason as plain "Queued"', () => {
		const queued = outbound({ channel: 'sms', status: 'queued', failure_message: null });
		expect(outboundEmailStatus(queued)).toEqual({
			label: 'Queued — not sent',
			tone: 'informative'
		});
	});

	it('reads a genuinely future scheduled_at as "Scheduled for ..." rather than plain "Queued"', () => {
		const scheduled = outbound({
			status: 'queued',
			failure_message: null,
			scheduled_at: new Date(Date.now() + 3_600_000).toISOString()
		});
		const result = outboundEmailStatus(scheduled);
		expect(result.tone).toBe('informative');
		expect(result.label.startsWith('Scheduled for ')).toBe(true);
	});

	it('does not read a scheduled_at only seconds out as "Scheduled" -- that is the worker draining it now', () => {
		const almostDue = outbound({
			channel: 'sms',
			status: 'queued',
			failure_message: null,
			scheduled_at: new Date(Date.now() + 5_000).toISOString()
		});
		expect(outboundEmailStatus(almostDue)).toEqual({
			label: 'Queued — not sent',
			tone: 'informative'
		});
	});
});

describe('placeTimelineNotes', () => {
	const day = (value: string) => value.slice(0, 10);
	const sameDay = (a: string, b: string) => day(a) === day(b);

	function note(id: string, created_at: string): TextStopNote {
		return { id, kind: 'stopped', phone: '+15550100', by_name: 'Sam', note: null, created_at };
	}

	const first = outbound({ id: 'm1', created_at: '2026-09-20T09:00:00.000Z' });
	const second = outbound({ id: 'm2', created_at: '2026-09-21T09:00:00.000Z' });

	it('puts a note between the two messages it falls between', () => {
		const placed = placeTimelineNotes(
			[first, second],
			[note('n1', '2026-09-20T12:00:00.000Z')],
			sameDay
		);
		expect(placed.before.get('m2')?.map((slot) => slot.note.id)).toEqual(['n1']);
		expect(placed.before.has('m1')).toBe(false);
		expect(placed.trailing).toEqual([]);
	});

	it('puts a note newer than every message at the end', () => {
		const placed = placeTimelineNotes(
			[first, second],
			[note('n1', '2026-09-21T15:00:00.000Z')],
			sameDay
		);
		expect(placed.before.size).toBe(0);
		expect(placed.trailing.map((slot) => slot.note.id)).toEqual(['n1']);
	});

	it('puts a note older than every message at the start', () => {
		const placed = placeTimelineNotes([first], [note('n1', '2026-09-19T08:00:00.000Z')], sameDay);
		expect(placed.before.get('m1')?.[0]).toMatchObject({ showDay: true });
	});

	it('draws a day divider only where the calendar day actually changes', () => {
		const placed = placeTimelineNotes(
			[first, second],
			[note('n1', '2026-09-20T12:00:00.000Z')],
			sameDay
		);
		// Same day as the first message: no divider before the note. The next message is a new day.
		expect(placed.before.get('m2')?.[0].showDay).toBe(false);
		expect(placed.messageShowsDay.get('m1')).toBe(true);
		expect(placed.messageShowsDay.get('m2')).toBe(true);
	});

	it('does not repeat a day divider on a message that follows a note from the same day', () => {
		const placed = placeTimelineNotes(
			[first, second],
			[note('n1', '2026-09-21T08:00:00.000Z')],
			sameDay
		);
		expect(placed.before.get('m2')?.[0].showDay).toBe(true);
		expect(placed.messageShowsDay.get('m2')).toBe(false);
	});

	it('compares moments, not text, so different fractional-second precision still orders correctly', () => {
		const placed = placeTimelineNotes(
			[outbound({ id: 'm1', created_at: '2026-09-21T09:00:00.5+00:00' })],
			[note('n1', '2026-09-21T09:00:00.123456+00:00')],
			sameDay
		);
		expect(placed.before.get('m1')).toHaveLength(1);
	});

	it('leaves messages untouched when there are no notes', () => {
		const placed = placeTimelineNotes([first, second], [], sameDay);
		expect(placed.before.size).toBe(0);
		expect(placed.trailing).toEqual([]);
		expect(placed.messageShowsDay.get('m1')).toBe(true);
		expect(placed.messageShowsDay.get('m2')).toBe(true);
	});
});

describe('Messenger in the inbox', () => {
	const origin = {
		page_name: 'Uplift Contractor',
		page_status: 'active' as const,
		display_name: null,
		last_inbound_at: '2026-10-23T02:00:00.000Z'
	};

	it('groups a Messenger lead under its client and finds the newest Page it wrote through', () => {
		const older = inbound({
			id: 'm-1',
			channel: 'messenger',
			sender_email: null,
			client_name: 'Facebook user',
			created_at: '2026-10-23T01:53:00.000Z',
			messenger: { ...origin, page_name: 'Old Page' }
		});
		const newer = inbound({
			id: 'm-2',
			channel: 'messenger',
			sender_email: null,
			client_name: 'Facebook user',
			created_at: '2026-10-23T02:00:00.000Z',
			messenger: origin
		});
		const groups = groupMessagesByContact([newer, older]);
		expect(groups).toHaveLength(1);
		expect(groups[0].name).toBe('Facebook user');
		expect(groups[0].guarded).toBe(false);
		expect(conversationMessenger(groups[0])?.page_name).toBe('Uplift Contractor');
	});

	it('has no Messenger origin for an email-only conversation', () => {
		expect(conversationMessenger({ messages: [inbound()] })).toBeNull();
	});

	it('keeps the reply window open for 24 hours after the last message, warning in the final hour', () => {
		const last = '2026-10-23T02:00:00.000Z';
		const at = (iso: string) => Date.parse(iso);
		expect(messengerReplyWindow(last, at('2026-10-23T02:43:00.000Z'))).toEqual({
			state: 'open',
			msLeft: (23 * 60 + 17) * 60_000
		});
		expect(messengerReplyWindow(last, at('2026-10-24T01:30:00.000Z')).state).toBe('closing');
		expect(messengerReplyWindow(last, at('2026-10-24T02:00:00.000Z')).state).toBe('closed');
		expect(messengerReplyWindow(null).state).toBe('closed');
	});

	it('says the time left in words', () => {
		expect(formatTimeLeft((23 * 60 + 17) * 60_000 + 30_000)).toBe('23 h 17 min');
		expect(formatTimeLeft(42 * 60_000)).toBe('42 min');
		expect(formatTimeLeft(5 * 60 * 60_000)).toBe('5 h');
	});
});

describe('messageRuns', () => {
	const sameDay = (a: string, b: string) => a.slice(0, 10) === b.slice(0, 10);
	const text = (id: string, at: string, direction: 'inbound' | 'outbound' = 'inbound') =>
		direction === 'inbound'
			? inbound({ id, channel: 'sms', created_at: at })
			: outbound({ id, channel: 'sms', created_at: at });

	it('joins bubbles from the same side a few minutes apart', () => {
		const runs = messageRuns(
			[
				text('a', '2026-10-23T09:00:00.000Z'),
				text('b', '2026-10-23T09:02:00.000Z'),
				text('c', '2026-10-23T09:03:00.000Z'),
				text('d', '2026-10-23T09:04:00.000Z', 'outbound')
			],
			sameDay
		);
		expect([...runs.values()]).toEqual(['first', 'middle', 'last', 'single']);
	});

	it('starts a new run after a long pause, on a new day, or around an email', () => {
		const runs = messageRuns(
			[
				text('a', '2026-10-23T09:00:00.000Z'),
				text('b', '2026-10-23T09:30:00.000Z'),
				text('c', '2026-10-24T09:31:00.000Z'),
				inbound({ id: 'd', created_at: '2026-10-24T09:32:00.000Z' })
			],
			sameDay
		);
		expect([...runs.values()]).toEqual(['single', 'single', 'single', 'single']);
	});
});
