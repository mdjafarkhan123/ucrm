import { createHash, randomBytes } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import {
	LAUNCH_APPROVAL_COLUMNS,
	launchApprovalWording,
	type LaunchApprovalRequest
} from '$lib/setup/launch-approval';

// Client onboarding E4: launch approval (plan §6). The private link the approver is emailed, the reads both sides
// make, the request email, the receipt, and the note that tells Jafar. The link follows the invoice and quote links
// (`$lib/server/invoices/access-links.ts`): 32 random bytes, and only their SHA-256 ever reaches the database.

type Client = SupabaseClient<Database>;

const TOKEN_BYTES = 32;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

// Postgres reads `bytea` from JSON as a hex literal. The raw token is never part of this string.
function hashLiteral(token: string) {
	return `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;
}

export function createLaunchApprovalToken() {
	const token = randomBytes(TOKEN_BYTES).toString('base64url');
	return { token, tokenHash: hashLiteral(token) };
}

/** Null for a token of the wrong shape, which is answered without touching the database. */
export function launchApprovalTokenHash(token: string | undefined) {
	if (!token || !TOKEN_PATTERN.test(token)) return null;
	return hashLiteral(token);
}

export const launchApprovalLinkUrl = (origin: string, token: string) => `${origin}/launch/${token}`;

// Rate-limit buckets for the public link, keyed by one-way values only, as the quote link's are.
export const launchLinkIpBucketKey = (action: string, ipAddress: string) =>
	`setup_launch_${action}_ip:${createHash('sha256').update(ipAddress, 'utf8').digest('hex')}`;
export const launchLinkTokenBucketKey = (action: string, tokenHashLiteral: string) =>
	`setup_launch_${action}_token:${tokenHashLiteral.slice(2)}`;

/**
 * Every request for a client, newest first. With the client's own session, row security shows them to its owners
 * and administrators; the link is not a column they can read. A client has a handful at most.
 */
export async function readLaunchApprovals(
	supabase: Client,
	organizationId: string
): Promise<LaunchApprovalRequest[]> {
	const { data, error } = await supabase
		.from('organization_setup_launch_approvals')
		.select(LAUNCH_APPROVAL_COLUMNS)
		.eq('organization_id', organizationId)
		.order('requested_at', { ascending: false });
	if (error) throw error;
	return data as unknown as LaunchApprovalRequest[];
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

export function greetingName(name: string | null) {
	const first = name?.trim().split(/\s+/)[0] ?? '';
	return first && !first.includes('@') ? first : 'there';
}

export function emailBody(
	paragraphs: string[],
	button: { label: string; url: string } | null,
	after: string
) {
	const htmlContent = [
		...paragraphs.map((line) => `<p>${escapeHtml(line)}</p>`),
		...(button
			? [
					`<p style="margin:20px 0"><a href="${escapeHtml(button.url)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">${escapeHtml(button.label)}</a></p>`
				]
			: []),
		`<p style="color:#6b7280;font-size:13px">${escapeHtml(after)}</p>`
	].join('\n');
	const textContent = [
		...paragraphs,
		...(button ? [`${button.label}: ${button.url}`] : []),
		after
	].join('\n\n');
	return { htmlContent, textContent };
}

export function buildLaunchApprovalRequestEmail(input: {
	approverName: string;
	organizationName: string;
	version: number;
	url: string;
}) {
	return {
		subject: `Please approve ${input.organizationName}'s system to go live`,
		...emailBody(
			[
				`Hi ${greetingName(input.approverName)}, Uplift has finished ${input.organizationName}'s system and checked it. You are named as the person who approves it before it goes live.`,
				`Open the link to look over preview version ${input.version}, then approve it or tell Uplift it is not ready yet. You do not need to sign in.`
			],
			{ label: 'Review and approve', url: input.url },
			'This link is private to you and works for 30 days. Nothing goes live until you approve it.'
		)
	};
}

/**
 * Emails the approver their private link. The outbox key carries when the link was sent, so sending the link again
 * sends a new email while a retry of the same send queues nothing twice.
 */
export async function sendLaunchApprovalRequestEmail(
	client: Client,
	input: {
		organizationId: string;
		requestId: string;
		linkSentAt: string;
		approverName: string;
		approverEmail: string;
		version: number;
		url: string;
	}
) {
	const organization = await client
		.from('organizations')
		.select('name')
		.eq('id', input.organizationId)
		.single();
	if (organization.error) throw organization.error;
	await enqueueEmailDelivery(client, {
		templateKey: 'client_setup_launch_approval_request',
		target: { targetKind: 'organization', targetId: input.organizationId },
		idempotencyKey: `setup-launch-ask:${input.requestId}:${input.linkSentAt}`,
		recipientEmail: input.approverEmail,
		...buildLaunchApprovalRequestEmail({
			approverName: input.approverName,
			organizationName: organization.data.name,
			version: input.version,
			url: input.url
		})
	});
}

export function buildLaunchApprovedEmail(input: {
	recipientName: string | null;
	organizationName: string;
	approvedByName: string;
	version: number;
	approvedAt: string;
	timeZone: string;
	origin: string;
}) {
	const when = new Intl.DateTimeFormat('en-GB', {
		dateStyle: 'long',
		timeStyle: 'short',
		timeZone: input.timeZone
	}).format(new Date(input.approvedAt));
	return {
		subject: `${input.organizationName}'s system is approved to go live`,
		...emailBody(
			[
				`Hi ${greetingName(input.recipientName)}, ${input.approvedByName} approved ${input.organizationName}'s system to go live on ${when}.`,
				`They agreed: “${launchApprovalWording(input.version)}”`,
				'Uplift is now preparing the launch and will let you know when it is live.'
			],
			{ label: 'See your project', url: `${input.origin}/setup` },
			'Keep this email as your receipt. If something needs to change, write to Uplift in Chat with Uplift.'
		)
	};
}

type Recipient = { user_id: string; email: string; name: string | null };

/**
 * The receipt, to the approver and the client's owners and administrators, once each. Keyed by the request, so a
 * retry queues only what is missing. Throws when nothing could be read or queued.
 */
export async function sendLaunchApprovedEmails(
	client: Client,
	input: { organizationId: string; requestId: string; origin: string }
) {
	const [requestResult, organizationResult, recipientsResult, readyResult] = await Promise.all([
		client
			.from('organization_setup_launch_approvals')
			.select('version, approver_name, approver_email, approved_at, approved_by_name, status')
			.eq('id', input.requestId)
			.single(),
		client.from('organizations').select('name').eq('id', input.organizationId).single(),
		client.rpc('owner_setup_review_recipients', { target_organization_id: input.organizationId }),
		client
			.from('organization_setup_ready')
			.select('time_zone')
			.eq('organization_id', input.organizationId)
			.maybeSingle()
	]);
	if (requestResult.error) throw requestResult.error;
	if (organizationResult.error) throw organizationResult.error;
	if (recipientsResult.error) throw recipientsResult.error;
	if (readyResult.error) throw readyResult.error;

	const request = requestResult.data;
	if (request.status !== 'approved' || !request.approved_at || !request.approved_by_name) return 0;

	const recipients = new Map<string, string | null>();
	recipients.set(request.approver_email.toLowerCase(), request.approver_name);
	for (const member of (recipientsResult.data ?? []) as unknown as Recipient[])
		if (!recipients.has(member.email.toLowerCase()))
			recipients.set(member.email.toLowerCase(), member.name);

	for (const [email, name] of recipients)
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_launch_approved',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-launch-approved:${input.requestId}:${email}`,
			recipientEmail: email,
			...buildLaunchApprovedEmail({
				recipientName: name,
				organizationName: organizationResult.data.name,
				approvedByName: request.approved_by_name,
				version: request.version,
				approvedAt: request.approved_at,
				timeZone: readyResult.data?.time_zone ?? 'UTC',
				origin: input.origin
			})
		});
	return recipients.size;
}

/** Tells Jafar in the Control Room that the approver approved, or said not yet. In-app only, as setup events are. */
export async function tellOwnerOfLaunchDecision(
	client: Client,
	input: {
		organizationId: string;
		decision: 'approved' | 'not_yet';
		version: number;
		origin: string;
	}
) {
	const organization = await client
		.from('organizations')
		.select('name')
		.eq('id', input.organizationId)
		.single();
	const name = organization.data?.name ?? 'A client';
	await raiseOwnerAlert(client, {
		kind: input.decision === 'approved' ? 'setup_launch_approved' : 'setup_launch_not_yet',
		severity: input.decision === 'approved' ? 'info' : 'attention',
		title:
			input.decision === 'approved'
				? `${name} approved preview version ${input.version} to go live`
				: `${name}'s approver said not yet to preview version ${input.version}`,
		body: input.decision === 'not_yet' ? 'Talk to them in Chat with Uplift.' : undefined,
		target: { targetKind: 'organization', targetId: input.organizationId },
		origin: input.origin
	});
}

/** After a decision is recorded: the receipt and Jafar's note for an approval, Jafar's note for a not yet. */
export async function followLaunchDecision(
	client: Client,
	input: {
		organizationId: string;
		requestId: string;
		version: number;
		decision: 'approved' | 'not_yet';
		origin: string;
	}
) {
	let emailed = true;
	if (input.decision === 'approved') {
		try {
			await sendLaunchApprovedEmails(client, input);
		} catch (error) {
			console.error('Could not queue the launch approval receipt.', error);
			emailed = false;
		}
	}
	try {
		await tellOwnerOfLaunchDecision(client, input);
	} catch (error) {
		console.error('Could not tell Jafar about the launch decision.', error);
	}
	return emailed;
}
