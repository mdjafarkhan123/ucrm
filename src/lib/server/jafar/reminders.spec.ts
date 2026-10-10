import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/env', () => ({
	getServerEnv: () => ({ SUPER_ADMIN_EMAIL: 'owner@example.com' })
}));
vi.mock('$lib/server/events/outbox', () => ({ createOwnerNotification: vi.fn() }));
vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));

import { createOwnerNotification } from '$lib/server/events/outbox';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import {
	buildReminderEmail,
	reminderWords,
	sendDuePlatformReminders,
	type DueReminder
} from './reminders';

const base: DueReminder = {
	id: '00000000-0000-0000-0000-000000000001',
	channel: 'in_app',
	fire_at: '2026-10-08T08:45:00Z',
	recipient_member_id: null,
	recipient_email: null,
	recipient_name: null,
	relationship_id: '00000000-0000-0000-0000-000000000002',
	business_name: 'Bright Roofing',
	call: null,
	follow_up: null,
	time_zone: 'Asia/Dhaka'
};

describe('reminderWords', () => {
	it('names a call, its day and how soon it starts in Jafar’s time zone', () => {
		const words = reminderWords(
			{
				...base,
				call: {
					id: 'c',
					title: null,
					starts_at: '2026-10-08T09:00:00Z',
					ends_at: '2026-10-08T09:30:00Z'
				}
			},
			new Date('2026-10-08T08:45:00Z')
		);
		expect(words.title).toBe('Call with Bright Roofing today at 3pm');
		expect(words.body).toBe('Starts in 15 minutes · 3pm–3:30pm with Bright Roofing.');
	});

	it('says tomorrow for a call a day away, without a countdown', () => {
		const words = reminderWords(
			{
				...base,
				call: {
					id: 'c',
					title: 'Discovery call',
					starts_at: '2026-10-09T09:30:00Z',
					ends_at: '2026-10-09T10:00:00Z'
				}
			},
			new Date('2026-10-08T09:30:00Z')
		);
		expect(words.title).toBe('Discovery call tomorrow at 3:30pm');
		expect(words.body).toBe('3:30pm–4pm with Bright Roofing.');
	});

	it('keeps a day-only follow-up on its own day, even far from UTC', () => {
		const words = reminderWords(
			{
				...base,
				time_zone: 'Pacific/Kiritimati',
				follow_up: { next_action: 'Send pricing', due_on: '2026-10-09', due_at: null }
			},
			// 09:00 on 9 October in Kiritimati (UTC+14).
			new Date('2026-10-08T19:00:00Z')
		);
		expect(words).toEqual({ title: 'Send pricing — Bright Roofing', body: 'Due today.' });
	});

	it('names another day by its weekday', () => {
		const words = reminderWords(
			{ ...base, follow_up: { next_action: 'Check in', due_on: '2026-10-12', due_at: null } },
			new Date('2026-10-08T03:00:00Z')
		);
		expect(words.body).toBe('Due Mon 12 Oct.');
	});
});

describe('buildReminderEmail', () => {
	it('escapes the words and links to the business', () => {
		const email = buildReminderEmail(
			{ title: 'Call <A&B>', body: 'Soon' },
			'https://app.test/jafar/leads/x',
			'https://app.test/jafar/preferences'
		);
		expect(email.subject).toBe('Reminder: Call <A&B>');
		expect(email.htmlContent).toContain('Call &lt;A&amp;B&gt;');
		expect(email.textContent).toContain('Open the business: https://app.test/jafar/leads/x');
	});
});

describe('sendDuePlatformReminders', () => {
	function clientHanding(due: DueReminder[]) {
		const rpc = vi.fn(async (name: string) =>
			name === 'claim_due_platform_reminders'
				? { data: due, error: null }
				: { data: true, error: null }
		);
		return { client: { rpc } as never, rpc };
	}

	it('puts a teammate’s reminder in their own bell and inbox, not Jafar’s (D3a)', async () => {
		const sam = {
			recipient_member_id: 'member-sam',
			recipient_email: 'sam@example.com',
			recipient_name: 'Sam Seller'
		};
		const { client, rpc } = clientHanding([
			{
				...base,
				...sam,
				follow_up: { next_action: 'Call back', due_on: '2026-10-08', due_at: null }
			},
			{
				...base,
				...sam,
				id: '00000000-0000-0000-0000-000000000003',
				channel: 'email',
				follow_up: { next_action: 'Call back', due_on: '2026-10-08', due_at: null }
			}
		]);

		expect(await sendDuePlatformReminders(client, { origin: 'https://app.test' })).toBe(2);
		expect(vi.mocked(createOwnerNotification)).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientMemberId: 'member-sam', correlationId: base.id })
		);
		expect(vi.mocked(enqueueEmailDelivery)).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientEmail: 'sam@example.com' })
		);
		expect(rpc).toHaveBeenCalledWith('record_platform_reminder_sent', { target_id: base.id });
	});

	it('sends Jafar’s own reminders to his bell and address', async () => {
		const { client } = clientHanding([
			{ ...base, follow_up: { next_action: 'Call back', due_on: '2026-10-08', due_at: null } },
			{ ...base, id: '00000000-0000-0000-0000-000000000004', channel: 'email' }
		]);

		await sendDuePlatformReminders(client, { origin: 'https://app.test' });
		expect(vi.mocked(createOwnerNotification)).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientMemberId: null })
		);
		expect(vi.mocked(enqueueEmailDelivery)).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientEmail: 'owner@example.com' })
		);
	});
});
