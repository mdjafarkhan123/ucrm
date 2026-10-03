import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { supportTopicLabel, type SupportTopic } from '$lib/support/api';

// Unseen-reply emails (D5b, plan §7 Follow-up; Intercom's unread-conversation email). When a reply in a
// support chat has gone unseen for 3 minutes, the person it was for gets one email with what they missed and an
// Open chat button. The database decides who is due and stops a second email until they open the chat; this
// writes the emails and queues them through the durable outbox. Runs on the email worker's once-a-minute wake.

// Each email is handed to the provider as it is queued, so a wake sends at most this many.
const BATCH = 20;

type UnseenMessage = {
	sender_name: string;
	body: string;
	attachment_count: number;
	created_at: string;
};

export type DueUnseenReply = {
	id: string;
	thread_id: string;
	organization_id: string;
	organization_name: string;
	// Null means the email is for Uplift.
	recipient_user_id: string | null;
	recipient_email: string | null;
	recipient_name: string | null;
	started_by_name: string | null;
	topic: SupportTopic;
	first_unseen_at: string;
	unseen_count: number;
	// The latest unseen messages, at most 5, oldest first.
	messages: UnseenMessage[];
};

type Email = { subject: string; htmlContent: string; textContent: string };

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

function filesNote(count: number) {
	if (count <= 0) return '';
	return count === 1
		? 'Sent a file — open the chat to see it.'
		: `Sent ${count} files — open the chat to see them.`;
}

function greetingName(name: string | null) {
	const first = name?.trim().split(/\s+/)[0] ?? '';
	return first && !first.includes('@') ? first : 'there';
}

function plural(count: number, word: string) {
	return `${count} ${word}${count === 1 ? '' : 's'}`;
}

function render(
	intro: string,
	reminder: DueUnseenReply,
	button: { label: string; url: string },
	footer: string[]
): Omit<Email, 'subject'> {
	const earlier = reminder.unseen_count - reminder.messages.length;
	const earlierNote = earlier > 0 ? `…and ${plural(earlier, 'earlier message')} in the chat.` : '';

	const messagesHtml = reminder.messages
		.map((message) => {
			const lines = [
				`<p style="margin:0 0 4px;font-weight:600;color:#111827">${escapeHtml(message.sender_name)}</p>`
			];
			if (message.body)
				lines.push(
					`<p style="margin:0;color:#374151;white-space:pre-wrap">${escapeHtml(message.body)}</p>`
				);
			const files = filesNote(message.attachment_count);
			if (files) lines.push(`<p style="margin:4px 0 0;color:#6b7280">${escapeHtml(files)}</p>`);
			return `<div style="margin:0 0 12px;padding:12px 16px;border-left:3px solid #d1d5db;background:#f9fafb">${lines.join('')}</div>`;
		})
		.join('\n');

	const htmlContent = [
		`<p>${escapeHtml(intro)}</p>`,
		earlierNote ? `<p style="color:#6b7280">${escapeHtml(earlierNote)}</p>` : '',
		messagesHtml,
		`<p style="margin:20px 0"><a href="${escapeHtml(button.url)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">${escapeHtml(button.label)}</a></p>`,
		...footer.map((line) => `<p style="color:#6b7280;font-size:13px">${escapeHtml(line)}</p>`)
	]
		.filter(Boolean)
		.join('\n');

	const textContent = [
		intro,
		earlierNote,
		...reminder.messages.map((message) =>
			[message.sender_name, message.body, filesNote(message.attachment_count)]
				.filter(Boolean)
				.join('\n')
		),
		`${button.label}: ${button.url}`,
		...footer
	]
		.filter(Boolean)
		.join('\n\n');

	return { htmlContent, textContent };
}

/** The email to a team member: Uplift's replies they have not seen. */
export function buildMemberEmail(reminder: DueUnseenReply, origin: string): Email {
	const topic = supportTopicLabel(reminder.topic);
	const replies = reminder.unseen_count === 1 ? 'a reply' : `${reminder.unseen_count} replies`;
	return {
		subject:
			reminder.unseen_count === 1
				? 'Uplift Support replied to your chat'
				: `Uplift Support sent ${replies} in your chat`,
		...render(
			`Hi ${greetingName(reminder.recipient_name)}, Uplift Support sent ${replies} in your ${topic} chat for ${reminder.organization_name}.`,
			reminder,
			{
				label: 'Open chat',
				url: `${origin}/dashboard?support_chat=${encodeURIComponent(reminder.thread_id)}`
			},
			[
				'Replies to this email are not read — answer in the chat instead.',
				'We will not email you again about this chat until you open it.'
			]
		)
	};
}

/** The email to Uplift: a member's messages waiting in the Support Inbox. */
export function buildUpliftEmail(reminder: DueUnseenReply, origin: string): Email {
	const topic = supportTopicLabel(reminder.topic);
	const who = reminder.messages.at(-1)?.sender_name ?? reminder.started_by_name ?? 'A team member';
	return {
		subject: `${reminder.organization_name}: ${plural(reminder.unseen_count, 'message')} waiting in Support`,
		...render(
			`${plural(reminder.unseen_count, 'message')} from ${reminder.organization_name} (${topic} chat, last from ${who}) ${reminder.unseen_count === 1 ? 'has' : 'have'} waited 3 minutes in the Support Inbox.`,
			reminder,
			{
				label: 'Open in Support Inbox',
				url: `${origin}/jafar/support?thread=${encodeURIComponent(reminder.thread_id)}`
			},
			[
				'Reply in the Support Inbox; replies to this email are not read.',
				'No further email about this chat until it is opened in the Support Inbox.'
			]
		)
	};
}

type QueuedEmail = Parameters<typeof enqueueEmailDelivery>[1];

// True once the email sits in the outbox. A send that fails after that is the outbox's to retry (an Operations
// row Jafar can retry), not this reminder's, so the reminder is stamped and never retried every minute.
async function queue(client: SupabaseClient<Database>, email: QueuedEmail) {
	try {
		await enqueueEmailDelivery(client, email);
		return true;
	} catch (error) {
		console.error('Could not send a support unseen-reply email.', error);
		const { data } = await client
			.from('platform_outbox_deliveries')
			.select('id')
			.eq('idempotency_key', email.idempotencyKey)
			.maybeSingle();
		return Boolean(data);
	}
}

/**
 * Queues every due unseen-reply email, up to one batch per wake. A reminder is stamped once its emails are in
 * the outbox; one that could not be queued stays due, and the next wake tries again under the same outbox
 * keys, so a retry never sends twice. Call it only from a wake holding the email worker's lease, so two wakes
 * never work the same reminders. Returns how many reminders were emailed.
 */
export async function sendDueSupportUnseenReplyEmails(
	client: SupabaseClient<Database>,
	options: { origin: string }
) {
	const { data, error } = await client.rpc('due_support_unseen_reply_emails', {
		batch_size: BATCH
	});
	if (error) throw error;
	const due = (data ?? []) as unknown as DueUnseenReply[];
	if (due.length === 0) return 0;

	// Uplift's copies go wherever Jafar's alerts go (Jafar settings).
	const upliftRecipients = due.some((reminder) => reminder.recipient_user_id === null)
		? ((await getOrCreateOwnerSettings(client)).alert_recipient_emails ?? [])
		: [];

	let emailed = 0;
	for (const reminder of due) {
		const target = { targetKind: 'organization' as const, targetId: reminder.organization_id };
		const stretch = `${reminder.id}:${reminder.first_unseen_at}`;
		let queued = true;
		if (reminder.recipient_user_id === null) {
			const email = buildUpliftEmail(reminder, options.origin);
			for (const recipient of upliftRecipients) {
				const ok = await queue(client, {
					templateKey: 'support_unseen_reply_uplift',
					target,
					idempotencyKey: `support-unseen:${stretch}:${recipient}`,
					recipientEmail: recipient,
					...email
				});
				queued &&= ok;
			}
		} else if (reminder.recipient_email) {
			queued = await queue(client, {
				templateKey: 'support_unseen_reply_member',
				target,
				idempotencyKey: `support-unseen:${stretch}`,
				recipientEmail: reminder.recipient_email,
				...buildMemberEmail(reminder, options.origin)
			});
		}
		if (!queued) continue;

		const { error: markError } = await client.rpc('mark_support_unseen_reply_emailed', {
			reminder_id: reminder.id,
			reminder_first_unseen_at: reminder.first_unseen_at
		});
		if (markError) console.error('Could not stamp a support unseen-reply reminder.', markError);
		else emailed += 1;
	}
	return emailed;
}
