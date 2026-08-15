import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { htmlToPlainText } from '$lib/server/jafar/message-templates';

type AdministratorEmailRecoveryNoticesParams = {
	organizationId: string;
	userId: string;
	oldEmail: string | null;
	newEmail: string;
	businessName: string;
};

/**
 * Two fixed, non-editable security notices (not an onboarding template) sent after an
 * administrator's login email has already been changed: a warning to the old address in case it
 * was not actually the administrator who requested this, and a confirmation to the new one.
 * Queued through the durable outbox so a Brevo outage becomes a retryable Operations row instead
 * of a silently lost notice. The old-address warning is skipped when the prior address could not
 * be resolved (a broken legacy auth record) -- the new address must still be confirmed, since
 * that is the whole point of the recovery.
 */
export async function sendAdministratorEmailRecoveryNotices(
	client: SupabaseClient<Database>,
	params: AdministratorEmailRecoveryNoticesParams
) {
	const target = { targetKind: 'organization' as const, targetId: params.organizationId };

	if (params.oldEmail) {
		const oldAddressBody = `<p>The login email for the ${params.businessName} administrator account was just changed away from this address by platform support.</p><p>If you did not request this, contact support immediately.</p>`;
		await enqueueEmailDelivery(client, {
			templateKey: 'administrator_email_recovery_old_address',
			target,
			idempotencyKey: `administrator-recovery:${params.userId}:${params.oldEmail}:old`,
			recipientEmail: params.oldEmail,
			subject: `Your ${params.businessName} login email was changed`,
			htmlContent: oldAddressBody,
			textContent: htmlToPlainText(oldAddressBody)
		});
	}

	const newAddressBody = `<p>This email is now the login address for the ${params.businessName} administrator account, changed by platform support after identity verification.</p><p>If you did not request this, contact support immediately.</p>`;
	await enqueueEmailDelivery(client, {
		templateKey: 'administrator_email_recovery_new_address',
		target,
		idempotencyKey: `administrator-recovery:${params.userId}:${params.newEmail}:new`,
		recipientEmail: params.newEmail,
		subject: `You can now sign in to ${params.businessName} with this email`,
		htmlContent: newAddressBody,
		textContent: htmlToPlainText(newAddressBody)
	});
}
