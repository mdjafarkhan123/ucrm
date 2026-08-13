import { createHash, randomBytes } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { renderTemplate, htmlToPlainText } from '$lib/server/jafar/message-templates';

const SETUP_LINK_TTL_MS = 24 * 60 * 60 * 1000;

function hashToken(token: string) {
	return createHash('sha256').update(token).digest('hex');
}

function setupEmailIdempotencyKey(applicationId: string) {
	return `application:${applicationId}:setup_email`;
}

type IssueSetupLinkParams = {
	applicationId: string;
	administratorUserId: string;
	intendedEmail: string;
	businessName: string;
	origin: string;
	actorEmail?: string;
};

/**
 * Creates (or replaces) the single active setup link for an application and emails it using
 * the published `password_setup` message template. The upsert always runs first, so a resend
 * overwrites the previous token hash before any network call -- the earlier raw token stops
 * matching any stored row even if the email send below then fails, which is what makes
 * "resend replaces the earlier unused link" true regardless of delivery outcome. The exact
 * rendered subject/body is stored on the same row, so Jafar can always see what was actually
 * sent even after the template's published wording later changes. A failed send is also
 * recorded as an operation attempt (so it appears on the Operations screen) and raises an
 * urgent owner notification -- this is the one delivery explicitly called out as an urgent
 * alert trigger in the onboarding contract.
 */
export async function issueSetupLink(
	client: SupabaseClient<Database>,
	params: IssueSetupLinkParams
) {
	const { data: template, error: templateError } = await client
		.from('platform_message_templates')
		.select('subject_published, body_published')
		.eq('template_key', 'password_setup')
		.maybeSingle();
	if (templateError) throw templateError;
	if (!template?.body_published) {
		throw new Error('The password setup email template has not been published yet.');
	}

	const token = randomBytes(32).toString('base64url');
	const tokenHash = hashToken(token);
	const expiresAt = new Date(Date.now() + SETUP_LINK_TTL_MS).toISOString();
	const link = `${params.origin}/setup-password?token=${token}`;
	const values = { business_name: params.businessName, setup_link: link };
	const subject = renderTemplate(template.subject_published ?? '', values);
	const body = renderTemplate(template.body_published, values);

	const { error: upsertError } = await client
		.from('platform_onboarding_application_setup_links')
		.upsert(
			{
				application_id: params.applicationId,
				administrator_user_id: params.administratorUserId,
				intended_email: params.intendedEmail,
				token_hash: tokenHash,
				expires_at: expiresAt,
				consumed_at: null,
				last_sent_at: new Date().toISOString(),
				last_error: null,
				rendered_subject: subject,
				rendered_body: body
			},
			{ onConflict: 'application_id' }
		);
	if (upsertError) throw upsertError;

	const target = { targetKind: 'onboarding_application' as const, targetId: params.applicationId };

	try {
		await sendTransactionalEmail({
			to: { email: params.intendedEmail },
			subject,
			htmlContent: body,
			textContent: htmlToPlainText(body)
		});
		await recordOperationOutcome(client, {
			operationType: 'setup_email_delivery',
			idempotencyKey: setupEmailIdempotencyKey(params.applicationId),
			target,
			success: true
		});
		return { sent: true as const };
	} catch (error) {
		console.error('Could not send the administrator setup email.', error);
		const message = error instanceof Error ? error.message : 'The setup email could not be sent.';
		await client
			.from('platform_onboarding_application_setup_links')
			.update({ last_error: message })
			.eq('application_id', params.applicationId);
		await recordOperationOutcome(client, {
			operationType: 'setup_email_delivery',
			idempotencyKey: setupEmailIdempotencyKey(params.applicationId),
			target,
			actorEmail: params.actorEmail,
			success: false,
			error: message
		});
		await raiseOwnerAlert(client, {
			kind: 'setup_email_failed',
			severity: 'urgent',
			title: `Setup email failed for ${params.businessName}`,
			body: message,
			target,
			origin: params.origin
		});
		return { sent: false as const, error: message };
	}
}
