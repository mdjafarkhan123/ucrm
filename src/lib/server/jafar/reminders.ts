import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { createOwnerNotification } from '$lib/server/events/outbox';
import { getServerEnv } from '$lib/server/env';

// Jafar business management C2: sends the Business Management calendar's reminders -- an alert in the bell or an
// email -- for sales calls and dated next actions (Google Calendar's notification model, plan § 6). The database
// writes each reminder from its call or next action and deletes the unsent ones when either moves, so whatever it
// hands over here is still right. It claims due reminders for five minutes and drops any more than an hour late.
// Runs on the email worker's once-a-minute wake. Each reminder goes to its call's or business's owner (D3a): an
// alert in their bell, an email to their sign-in address; null is Jafar.

const BATCH = 50;

export type DueReminder = {
	id: string;
	channel: 'in_app' | 'email';
	fire_at: string;
	/** Null is Jafar. */
	recipient_member_id: string | null;
	recipient_email: string | null;
	recipient_name: string | null;
	relationship_id: string;
	business_name: string;
	call: { id: string; title: string | null; starts_at: string; ends_at: string } | null;
	follow_up: { next_action: string | null; due_on: string | null; due_at: string | null } | null;
	time_zone: string;
};

type Words = { title: string; body: string };

function formatter(zone: string, options: Intl.DateTimeFormatOptions) {
	return new Intl.DateTimeFormat('en-GB', { timeZone: zone, ...options });
}

/** An instant's day in a time zone, as "2026-10-09". */
function dayOf(instant: Date, zone: string) {
	return new Intl.DateTimeFormat('en-CA', {
		timeZone: zone,
		year: 'numeric',
		month: '2-digit',
		day: '2-digit'
	}).format(instant);
}

/** 3pm, 3:30pm. */
function clock(iso: string, zone: string) {
	const parts = formatter(zone, { hour: 'numeric', minute: '2-digit', hour12: true })
		.formatToParts(new Date(iso))
		.reduce<Record<string, string>>((all, part) => ({ ...all, [part.type]: part.value }), {});
	const minute = parts.minute === '00' ? '' : `:${parts.minute}`;
	return `${parts.hour}${minute}${(parts.dayPeriod ?? '').toLowerCase().replace(/\./g, '')}`;
}

/** "today", "tomorrow", or "Thu 9 Oct" for a day ("2026-10-09"), counted from `now` in the time zone. */
function dayWords(day: string, now: Date, zone: string) {
	if (day === dayOf(now, zone)) return 'today';
	if (day === dayOf(new Date(now.getTime() + 24 * 60 * 60 * 1000), zone)) return 'tomorrow';
	return new Intl.DateTimeFormat('en-GB', {
		timeZone: 'UTC',
		weekday: 'short',
		day: 'numeric',
		month: 'short'
	}).format(new Date(`${day}T00:00:00Z`));
}

/** "today at 3pm" for an instant. */
function momentWords(iso: string, now: Date, zone: string) {
	return `${dayWords(dayOf(new Date(iso), zone), now, zone)} at ${clock(iso, zone)}`;
}

/** What the alert or email says. `now` is when it goes out. */
export function reminderWords(reminder: DueReminder, now = new Date()): Words {
	const zone = reminder.time_zone;
	if (reminder.call) {
		const { call } = reminder;
		const subject = call.title ?? `Call with ${reminder.business_name}`;
		const when = momentWords(call.starts_at, now, zone);
		const minutes = Math.round((Date.parse(call.starts_at) - now.getTime()) / 60_000);
		const soon =
			minutes <= 0 ? 'Starting now' : minutes < 60 ? `Starts in ${minutes} minutes` : null;
		return {
			title: `${subject} ${when}`,
			body: [
				soon,
				`${clock(call.starts_at, zone)}–${clock(call.ends_at, zone)} with ${reminder.business_name}.`
			]
				.filter(Boolean)
				.join(' · ')
		};
	}
	const action = reminder.follow_up?.next_action ?? 'Follow up';
	const due = reminder.follow_up?.due_at
		? momentWords(reminder.follow_up.due_at, now, zone)
		: reminder.follow_up?.due_on
			? dayWords(reminder.follow_up.due_on, now, zone)
			: null;
	return {
		title: `${action} — ${reminder.business_name}`,
		body: due ? `Due ${due}.` : 'Your next step with this business.'
	};
}

const HTML_ESCAPE: Record<string, string> = {
	'&': '&amp;',
	'<': '&lt;',
	'>': '&gt;',
	'"': '&quot;',
	"'": '&#39;'
};

function escapeHtml(value: string) {
	return value.replace(/[&<>"']/g, (character) => HTML_ESCAPE[character] ?? character);
}

export function buildReminderEmail(words: Words, leadUrl: string, preferencesUrl: string) {
	const subject = `Reminder: ${words.title}`;
	const htmlContent = [
		`<p style="margin:0 0 4px;font-weight:600;color:#111827">${escapeHtml(words.title)}</p>`,
		`<p style="margin:0;color:#374151">${escapeHtml(words.body)}</p>`,
		`<p style="margin:20px 0"><a href="${escapeHtml(leadUrl)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">Open the business</a></p>`,
		`<p style="color:#6b7280;font-size:13px">Change when reminders come in <a href="${escapeHtml(preferencesUrl)}" style="color:#6b7280">My preferences</a>.</p>`
	].join('\n');
	const textContent = [
		words.title,
		words.body,
		`Open the business: ${leadUrl}`,
		`Change when reminders come in My preferences: ${preferencesUrl}`
	].join('\n\n');
	return { subject, htmlContent, textContent };
}

function isDuplicate(error: unknown) {
	return (error as { code?: string } | null)?.code === '23505';
}

async function deliver(
	client: SupabaseClient<Database>,
	reminder: DueReminder,
	origin: string,
	ownerEmail: string
) {
	const words = reminderWords(reminder);
	if (reminder.channel === 'in_app') {
		try {
			await createOwnerNotification(client, {
				kind: 'business_reminder',
				severity: 'attention',
				title: words.title.slice(0, 200),
				body: words.body,
				target: { targetKind: 'business_relationship', targetId: reminder.relationship_id },
				correlationId: reminder.id,
				recipientMemberId: reminder.recipient_member_id
			});
		} catch (error) {
			// One alert per reminder: a retry after a lost lease finds the first one already there.
			if (!isDuplicate(error)) throw error;
		}
		return;
	}
	await enqueueEmailDelivery(client, {
		templateKey: 'platform_reminder',
		target: { targetKind: 'platform', targetId: null },
		idempotencyKey: `platform-reminder:${reminder.id}`,
		recipientEmail: reminder.recipient_email ?? ownerEmail,
		...buildReminderEmail(
			words,
			`${origin}/jafar/leads/${encodeURIComponent(reminder.relationship_id)}`,
			`${origin}/jafar/settings/preferences`
		)
	});
}

/**
 * Sends every reminder that is due, up to one batch per wake. One that fails stays claimed; after five minutes the
 * next wake claims it again, and the alert's correlation id and the email's outbox key keep it from going twice.
 * Call it only from a wake holding the email worker's lease. Returns how many went out.
 */
export async function sendDuePlatformReminders(
	client: SupabaseClient<Database>,
	options: { origin: string }
) {
	const { data, error } = await client.rpc('claim_due_platform_reminders', { batch_size: BATCH });
	if (error) throw error;
	const due = (data ?? []) as unknown as DueReminder[];
	if (due.length === 0) return 0;

	const ownerEmail = getServerEnv().SUPER_ADMIN_EMAIL;
	let sent = 0;
	for (const reminder of due) {
		try {
			await deliver(client, reminder, options.origin, ownerEmail);
		} catch (error) {
			console.error('Could not send a calendar reminder.', error);
			continue;
		}
		const recorded = await client.rpc('record_platform_reminder_sent', { target_id: reminder.id });
		if (recorded.error) console.error('Could not record a calendar reminder.', recorded.error);
		else sent += 1;
	}
	return sent;
}
