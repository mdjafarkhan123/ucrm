import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { readSetupServiceKeys } from '$lib/server/setup/catalogue';
import {
	PROVIDER_WAIT_TITLE,
	providerWaitsFor,
	providerWaitsFromRows,
	type ProviderWait,
	type ProviderWaitKey
} from '$lib/setup/provider-waits';

// Client onboarding E2: outside waits (plan §5). Jafar's reads and the email that goes out when a wait needs the
// client — "You need to do something" is Uplift asking for something, not a reminder, so like a returned section
// it reaches every owner and administrator regardless of reminder opt-outs. One email per person per change:
// the outbox key carries the change's time.

type Client = SupabaseClient<Database>;

const WAIT_COLUMNS = 'wait_key, status, note, updated_at';

/** The waits a client's own owners and administrators may read, through their own session. */
export async function readClientProviderWaits(
	supabase: Client,
	organizationId: string
): Promise<ProviderWait[] | null> {
	const { data, error } = await supabase
		.from('organization_setup_provider_waits')
		.select(WAIT_COLUMNS)
		.eq('organization_id', organizationId);
	if (error) {
		console.error('Could not read the outside waits.', error);
		return null;
	}
	return providerWaitsFromRows(data);
}

/** Jafar's view: the waits the package offers, and those started. Throws when the database cannot be read. */
export async function readOwnerProviderWaits(supabase: Client, organizationId: string) {
	const [serviceKeys, waits] = await Promise.all([
		readSetupServiceKeys(supabase, organizationId),
		readClientProviderWaits(supabase, organizationId)
	]);
	if (!serviceKeys || !waits) throw new Error('The outside waits could not be read.');
	return { offered: providerWaitsFor([...serviceKeys]), waits };
}

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

export function buildProviderWaitEmail(input: {
	recipientName: string | null;
	organizationName: string;
	waitKey: ProviderWaitKey;
	note: string;
	origin: string;
}) {
	const title = PROVIDER_WAIT_TITLE[input.waitKey];
	const url = `${input.origin}/setup#outside-waits`;
	const paragraphs = [
		`Hi ${greetingName(input.recipientName)}, Uplift is setting up ${input.organizationName}'s ${title.toLowerCase()}, and the next step needs you.`,
		`Uplift can't do this part for you — it has to come from the business.`
	];
	const after = `Not sure what we mean? Use Ask Uplift on your Setup page and we'll walk you through it.`;

	const htmlContent = [
		...paragraphs.map((line) => `<p>${escapeHtml(line)}</p>`),
		`<div style="margin:16px 0;padding:12px 16px;border-left:3px solid #d97706;background:#fffbeb"><p style="margin:0 0 4px;font-weight:600;color:#111827">What to do</p><p style="margin:0;color:#374151;white-space:pre-line">${escapeHtml(input.note)}</p></div>`,
		`<p style="margin:20px 0"><a href="${escapeHtml(url)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">Open your Setup page</a></p>`,
		`<p style="color:#6b7280;font-size:13px">${escapeHtml(after)}</p>`
	].join('\n');
	const textContent = [
		...paragraphs,
		`What to do:\n${input.note}`,
		`Open your Setup page: ${url}`,
		after
	].join('\n\n');

	return { subject: `Your ${title.toLowerCase()} needs you`, htmlContent, textContent };
}

/**
 * Queues the email about a wait that needs the client, if it still does. Call it with the service role's client
 * after the change is recorded. Throws when nothing could be read or queued.
 */
export async function sendProviderWaitEmails(
	client: Client,
	input: { organizationId: string; waitKey: ProviderWaitKey; origin: string }
) {
	const [waitResult, organizationResult, recipientsResult] = await Promise.all([
		client
			.from('organization_setup_provider_waits')
			.select('status, note, updated_at')
			.eq('organization_id', input.organizationId)
			.eq('wait_key', input.waitKey)
			.maybeSingle(),
		client.from('organizations').select('name').eq('id', input.organizationId).single(),
		client.rpc('owner_setup_review_recipients', { target_organization_id: input.organizationId })
	]);
	if (waitResult.error) throw waitResult.error;
	if (organizationResult.error) throw organizationResult.error;
	if (recipientsResult.error) throw recipientsResult.error;

	const wait = waitResult.data;
	if (wait?.status !== 'action_needed' || !wait.note) return 0;

	const recipients = (recipientsResult.data ?? []) as unknown as Recipient[];
	for (const recipient of recipients)
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_provider_action_needed',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-provider-wait:${input.organizationId}:${input.waitKey}:${wait.updated_at}:${recipient.user_id}`,
			recipientEmail: recipient.email,
			...buildProviderWaitEmail({
				recipientName: recipient.name,
				organizationName: organizationResult.data.name,
				waitKey: input.waitKey,
				note: wait.note,
				origin: input.origin
			})
		});
	return recipients.length;
}
