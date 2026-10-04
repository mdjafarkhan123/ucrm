import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { readSetupCatalogue, readSetupServiceKeys } from '$lib/server/setup/catalogue';
import { readSetupState, setupSummary } from '$lib/server/setup/read';
import { catalogueForServices } from '$lib/setup/catalogue';
import { SETUP_CHECK_DESCRIPTION, SETUP_CHECK_KEY, SETUP_CHECK_TITLE } from '$lib/setup/check';

// Setup reminder emails (C6, plan §5; Intercom's and Customer.io's inactivity-triggered onboarding nudges). When
// a paid client's setup has sat untouched for about 24 hours, 3 days and 7 days, its owners and administrators
// get an email pointing at the next unfinished task. Any setup activity restarts the clock. The database
// decides when a reminder is due, keeps it to the business's daytime, and stops it for a paused account; this
// checks setup is still unfinished, writes the email and queues it through the durable outbox. Runs on the
// email worker's once-a-minute wake.

const BATCH = 20;

// While a support message of theirs waits on Uplift, the move is Uplift's: look again in a day.
const SUPPORT_WAIT_MS = 24 * 60 * 60 * 1000;

type Recipient = { user_id: string; email: string; name: string | null };

export type DueSetupReminder = {
	organization_id: string;
	organization_name: string;
	last_activity_at: string;
	// Reminders already sent in this quiet stretch; this one is number reminders_sent + 1.
	reminders_sent: number;
	support_waiting: boolean;
	recipients: Recipient[];
};

export type ReminderTask = { key: string; title: string; description: string };

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

function greetingName(name: string | null) {
	const first = name?.trim().split(/\s+/)[0] ?? '';
	return first && !first.includes('@') ? first : 'there';
}

/** One reminder email. `step` is 1, 2 or 3; the third says it is the last. */
export function buildSetupReminderEmail(input: {
	step: number;
	recipientName: string | null;
	organizationName: string;
	task: ReminderTask;
	progress: { done: number; total: number };
	origin: string;
}): Email {
	const { step, organizationName, task, progress, origin } = input;
	const taskUrl = `${origin}/setup/${encodeURIComponent(task.key)}`;
	const settingsUrl = `${origin}/setup#reminder-emails`;

	const subject =
		step === 1
			? `Next step for ${organizationName}: ${task.title}`
			: step === 2
				? `Pick up your Uplift setup where you left off`
				: `Last reminder: finish your setup so Uplift can start building`;

	const opening =
		step === 1
			? `Hi ${greetingName(input.recipientName)}, your Uplift setup for ${organizationName} is waiting for you.`
			: step === 2
				? `Hi ${greetingName(input.recipientName)}, it has been a few days since anyone worked on the Uplift setup for ${organizationName}.`
				: `Hi ${greetingName(input.recipientName)}, the Uplift setup for ${organizationName} has been quiet for a week. This is our last reminder.`;

	const progressLine =
		progress.done === 0
			? `No tasks are done yet — the first one takes a few minutes.`
			: `${progress.done} of ${progress.total} tasks are done.`;

	const paragraphs = [
		opening,
		progressLine,
		`Uplift starts building your system once you send your setup to us, so the sooner it is finished, the sooner you are live. Every answer saves on its own, so you can do a little at a time.`
	];
	const footer = [
		`Stuck on a question? Choose "I need Uplift's help" on it and carry on, or ask us with Chat with Uplift on any screen.`,
		`Don't want these reminders? Turn them off on your setup page: ${settingsUrl}`
	];

	const htmlContent = [
		...paragraphs.map((line) => `<p>${escapeHtml(line)}</p>`),
		`<div style="margin:16px 0;padding:12px 16px;border-left:3px solid #d1d5db;background:#f9fafb"><p style="margin:0 0 4px;font-weight:600;color:#111827">Next: ${escapeHtml(task.title)}</p><p style="margin:0;color:#374151">${escapeHtml(task.description)}</p></div>`,
		`<p style="margin:20px 0"><a href="${escapeHtml(taskUrl)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">Continue setup</a></p>`,
		`<p style="color:#6b7280;font-size:13px">${escapeHtml(footer[0])}</p>`,
		`<p style="color:#6b7280;font-size:13px">Don't want these reminders? <a href="${escapeHtml(settingsUrl)}" style="color:#6b7280">Turn them off on your setup page</a>.</p>`
	].join('\n');

	const textContent = [
		...paragraphs,
		`Next: ${task.title}\n${task.description}`,
		`Continue setup: ${taskUrl}`,
		...footer
	].join('\n\n');

	return { subject, htmlContent, textContent };
}

type QueuedEmail = Parameters<typeof enqueueEmailDelivery>[1];

// True once the email sits in the outbox; a later send failure is the outbox's to retry.
async function queue(client: SupabaseClient<Database>, email: QueuedEmail) {
	try {
		await enqueueEmailDelivery(client, email);
		return true;
	} catch (error) {
		console.error('Could not queue a setup reminder email.', error);
		const { data } = await client
			.from('platform_outbox_deliveries')
			.select('id')
			.eq('idempotency_key', email.idempotencyKey)
			.maybeSingle();
		return Boolean(data);
	}
}

async function record(
	client: SupabaseClient<Database>,
	reminder: DueSetupReminder,
	outcome: 'sent' | 'finished' | 'later',
	lookAgainAt?: string
) {
	const { error } = await client.rpc('record_organization_setup_reminder', {
		target_organization_id: reminder.organization_id,
		seen_last_activity_at: reminder.last_activity_at,
		outcome,
		look_again_at: lookAgainAt
	});
	if (error) console.error('Could not record a setup reminder.', error);
	return !error;
}

/**
 * Queues every due setup reminder, up to one batch per wake. A reminder whose emails could not all be queued
 * stays due, and the next wake retries under the same outbox keys, so nobody is emailed twice. Call it only
 * from a wake holding the email worker's lease. Returns how many reminders went out.
 */
export async function sendDueSetupReminderEmails(
	client: SupabaseClient<Database>,
	options: { origin: string }
) {
	const { data, error } = await client.rpc('due_organization_setup_reminders', {
		batch_size: BATCH
	});
	if (error) throw error;
	const due = (data ?? []) as unknown as DueSetupReminder[];
	if (due.length === 0) return 0;

	// One read for the whole batch: every reminder counts against the setup version published now.
	const catalogue = await readSetupCatalogue(client);
	if (!catalogue) throw new Error('The published setup version could not be read.');

	let sent = 0;
	for (const reminder of due) {
		const [state, serviceKeys] = await Promise.all([
			readSetupState(client, reminder.organization_id),
			readSetupServiceKeys(client, reminder.organization_id)
		]);
		if (!state || !serviceKeys) continue;
		const summary = setupSummary(state, catalogueForServices(catalogue, serviceKeys));
		// B13: with every task done, the next step is Check and send, until setup has been sent.
		const next =
			summary.next?.key === SETUP_CHECK_KEY
				? { key: SETUP_CHECK_KEY, title: SETUP_CHECK_TITLE, description: SETUP_CHECK_DESCRIPTION }
				: summary.next && summary.sections.find((section) => section.key === summary.next?.key);

		// Nothing left for the client to do: setup has been sent.
		if (!next) {
			await record(client, reminder, 'finished');
			continue;
		}
		if (reminder.support_waiting) {
			await record(client, reminder, 'later', new Date(Date.now() + SUPPORT_WAIT_MS).toISOString());
			continue;
		}

		const step = reminder.reminders_sent + 1;
		let queued = true;
		for (const recipient of reminder.recipients) {
			const ok = await queue(client, {
				templateKey: 'client_setup_reminder',
				target: { targetKind: 'organization', targetId: reminder.organization_id },
				idempotencyKey: `setup-reminder:${reminder.organization_id}:${reminder.last_activity_at}:${step}:${recipient.user_id}`,
				recipientEmail: recipient.email,
				...buildSetupReminderEmail({
					step,
					recipientName: recipient.name,
					organizationName: reminder.organization_name,
					task: next,
					progress: summary.progress,
					origin: options.origin
				})
			});
			queued &&= ok;
		}
		// With everyone opted out the reminder still counts, so the timer moves on rather than asking again.
		if (queued && (await record(client, reminder, 'sent'))) sent += 1;
	}
	return sent;
}
