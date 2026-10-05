import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import {
	createLaunchApprovalToken,
	launchApprovalLinkUrl,
	readLaunchApprovals,
	sendLaunchApprovalRequestEmail
} from '$lib/server/setup/launch-approval';
import { setupPreviewVersionSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E4 (plan §6): every launch approval request for one client, newest first (GET), and Jafar's
// Ask for launch approval on the newest released preview (POST), which emails the final approver a private link.
// The request stands even if the email cannot be queued, and the reply says so; Send the link again retries it.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');
	try {
		const requests = await readLaunchApprovals(getOwnerSupabaseClient(), organizationId.data);
		return json({ requests }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read the launch approvals.', error);
		return databaseError();
	}
};

type AskResult = {
	status: 'requested' | 'already_requested' | 'already_approved';
	request_id: string;
	approver_name?: string;
	approver_email?: string;
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const organizationId = z.uuid().safeParse(event.params.organizationId);
	if (!organizationId.success) return notFound('That client does not exist.');

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupPreviewVersionSchema.safeParse(body);
	if (!parsed.success) return validationError({ form: 'Choose a preview.' });

	const client = getOwnerSupabaseClient();
	const { token, tokenHash } = createLaunchApprovalToken();
	const { data, error } = await client.rpc('owner_request_setup_launch_approval', {
		target_organization_id: organizationId.data,
		target_version: parsed.data.version,
		new_token_hash: tokenHash,
		actor_email: session.email
	});
	if (error) {
		if (error.code === '23514') return validationError({ form: error.message });
		console.error('Could not ask for launch approval.', error);
		return databaseError();
	}
	const result = data as unknown as AskResult;
	if (result.status !== 'requested') return json(result, { headers: NO_STORE_HEADERS });

	let emailed = true;
	try {
		const request = await client
			.from('organization_setup_launch_approvals')
			.select('link_sent_at')
			.eq('id', result.request_id)
			.single();
		if (request.error) throw request.error;
		await sendLaunchApprovalRequestEmail(client, {
			organizationId: organizationId.data,
			requestId: result.request_id,
			linkSentAt: request.data.link_sent_at,
			approverName: result.approver_name ?? '',
			approverEmail: result.approver_email ?? '',
			version: parsed.data.version,
			url: launchApprovalLinkUrl(env.APP_URL?.trim() || event.url.origin, token)
		});
	} catch (error) {
		console.error('Could not queue the launch approval email.', error);
		emailed = false;
	}
	return json({ ...result, emailed }, { headers: NO_STORE_HEADERS });
};
