import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { readSetupSectionTitles, setupSectionLabel } from '$lib/server/setup/catalogue';

// Client onboarding C3b: when Uplift sends a setup section back, the client's owners and administrators are
// emailed at once with a link straight to that section (Jafar, 2026-10-04; Content Snare emails the client when
// a request is sent back). It is Uplift asking for something, not a reminder, so a reminder opt-out does not hold
// it back. One email per person per decision: the outbox key carries the decision's time, so pressing Send back
// again with the same note re-queues nothing that is already queued and fills in anything that was missed.

type Recipient = { user_id: string; email: string; name: string | null };

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

export function buildSetupReturnEmail(input: {
	recipientName: string | null;
	organizationName: string;
	sectionKey: string;
	sectionTitle: string;
	note: string;
	questionCount: number;
	origin: string;
}) {
	const url = `${input.origin}/setup/${encodeURIComponent(input.sectionKey)}`;
	const questions =
		input.questionCount === 0
			? 'Open the task to see what to change.'
			: input.questionCount === 1
				? 'The question to change is highlighted on the task.'
				: `The ${input.questionCount} questions to change are highlighted on the task.`;
	const paragraphs = [
		`Hi ${greetingName(input.recipientName)}, Uplift looked over the setup ${input.organizationName} sent and needs a change to “${input.sectionTitle}” before carrying on.`,
		`Everything else you sent stays as it is — only this task needs another look. ${questions}`
	];
	const after = `When you have made the change, send your setup to Uplift again from Check and send. Not sure what we mean? Use Ask Uplift on the task.`;

	const htmlContent = [
		...paragraphs.map((line) => `<p>${escapeHtml(line)}</p>`),
		`<div style="margin:16px 0;padding:12px 16px;border-left:3px solid #d97706;background:#fffbeb"><p style="margin:0 0 4px;font-weight:600;color:#111827">Uplift's note</p><p style="margin:0;color:#374151;white-space:pre-line">${escapeHtml(input.note)}</p></div>`,
		`<p style="margin:20px 0"><a href="${escapeHtml(url)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">Open ${escapeHtml(input.sectionTitle)}</a></p>`,
		`<p style="color:#6b7280;font-size:13px">${escapeHtml(after)}</p>`
	].join('\n');
	const textContent = [
		...paragraphs,
		`Uplift's note:\n${input.note}`,
		`Open ${input.sectionTitle}: ${url}`,
		after
	].join('\n\n');

	return {
		subject: `Uplift needs a change to ${input.sectionTitle}`,
		htmlContent,
		textContent
	};
}

/**
 * Queues the email about a section Uplift has sent back, if that is still Uplift's decision on it. Call it with
 * the service role's client after the decision is recorded. Throws when nothing could be read or queued.
 */
export async function sendSetupReturnEmails(
	client: SupabaseClient<Database>,
	input: { organizationId: string; sectionKey: string; origin: string }
) {
	const [reviewResult, organizationResult, recipientsResult, titles] = await Promise.all([
		client
			.from('organization_setup_section_reviews')
			.select('decision, note, question_keys, reviewed_at')
			.eq('organization_id', input.organizationId)
			.eq('section_key', input.sectionKey)
			.maybeSingle(),
		client.from('organizations').select('name').eq('id', input.organizationId).single(),
		client.rpc('owner_setup_review_recipients', { target_organization_id: input.organizationId }),
		readSetupSectionTitles(client, input.organizationId)
	]);
	if (reviewResult.error) throw reviewResult.error;
	if (organizationResult.error) throw organizationResult.error;
	if (recipientsResult.error) throw recipientsResult.error;

	const review = reviewResult.data;
	if (review?.decision !== 'returned' || !review.note) return 0;

	const recipients = (recipientsResult.data ?? []) as unknown as Recipient[];
	const sectionTitle = setupSectionLabel(titles, input.sectionKey) ?? 'Setup';
	for (const recipient of recipients)
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_section_returned',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-return:${input.organizationId}:${input.sectionKey}:${review.reviewed_at}:${recipient.user_id}`,
			recipientEmail: recipient.email,
			...buildSetupReturnEmail({
				recipientName: recipient.name,
				organizationName: organizationResult.data.name,
				sectionKey: input.sectionKey,
				sectionTitle,
				note: review.note,
				questionCount: review.question_keys.length,
				origin: input.origin
			})
		});
	return recipients.length;
}
