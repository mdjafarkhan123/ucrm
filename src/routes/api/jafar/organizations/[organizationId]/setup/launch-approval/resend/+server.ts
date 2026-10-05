import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import {
	createLaunchApprovalToken,
	launchApprovalLinkUrl,
	sendLaunchApprovalRequestEmail
} from '$lib/server/setup/launch-approval';

// Client onboarding E4 (plan §6): a fresh private link for the open request, emailed to the approver; the link
// emailed before stops working, since only its hash was ever kept.

type ResendResult = {
	request_id: string;
	approver_name: string;
	approver_email: string;
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	const client = getOwnerSupabaseClient();
	const { token, tokenHash } = createLaunchApprovalToken();
	const { data, error } = await client.rpc('owner_resend_setup_launch_approval', {
		target_organization_id: organizationId.data,
		new_token_hash: tokenHash,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not send the launch approval link again.', error);
		return databaseError();
	}
	const result = data as unknown as ResendResult;

	let emailed = true;
	try {
		const request = await client
			.from('organization_setup_launch_approvals')
			.select('link_sent_at, version')
			.eq('id', result.request_id)
			.single();
		if (request.error) throw request.error;
		await sendLaunchApprovalRequestEmail(client, {
			organizationId: organizationId.data,
			requestId: result.request_id,
			linkSentAt: request.data.link_sent_at,
			approverName: result.approver_name,
			approverEmail: result.approver_email,
			version: request.data.version,
			url: launchApprovalLinkUrl(env.APP_URL?.trim() || event.url.origin, token)
		});
	} catch (error) {
		console.error('Could not queue the launch approval email.', error);
		emailed = false;
	}
	return json({ status: 'resent', emailed }, { headers: NO_STORE_HEADERS });
};
