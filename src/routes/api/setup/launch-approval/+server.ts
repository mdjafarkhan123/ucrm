import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import {
	requireSetupEditor,
	requireSetupReader,
	setupWriteError,
	setupWriteLimited
} from '$lib/server/setup/access';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { env } from '$env/dynamic/private';
import { followLaunchDecision, readLaunchApprovals } from '$lib/server/setup/launch-approval';
import { currentLaunchApproval } from '$lib/setup/launch-approval';
import { setupLaunchDecisionSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E4 (plan §6): the open launch approval request or the standing approval (GET), and the named
// approver's answer on the Setup page (POST). Only the final approver named in the newest send may answer; anyone
// else on the team sees who is being asked. Read with the client's own session, so row security applies.

export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	try {
		const request = currentLaunchApproval(
			await readLaunchApprovals(event.locals.supabase, check.auth.organization.id)
		);
		const email = check.auth.user.email?.trim().toLowerCase() ?? null;
		return json(
			{
				request,
				is_approver: request !== null && email === request.approver_email.toLowerCase()
			},
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read the launch approval.', error);
		return databaseError();
	}
};

type DecisionResult = {
	status: 'approved' | 'not_yet' | 'already_approved';
	request_id: string;
	version?: number;
};

export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;

	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupLaunchDecisionSchema.safeParse(body);
	if (!parsed.success)
		return validationError({ form: parsed.error.issues[0]?.message ?? 'Check your answer.' });

	const { data, error } = await event.locals.supabase.rpc('client_decide_setup_launch', {
		target_organization_id: organizationId,
		target_version: parsed.data.version,
		decision: parsed.data.decision,
		note: parsed.data.note ?? undefined
	});
	// "Only <approver> can approve the launch." says who may, which the general setup refusal would not.
	if (error?.code === '42501' && error.message.endsWith('can approve the launch.'))
		return json({ error: error.message, reason: 'not_approver' }, { status: 403 });
	if (error) return setupWriteError(error);
	const result = data as unknown as DecisionResult;

	let emailed = true;
	if (result.status === 'approved' || result.status === 'not_yet')
		emailed = await followLaunchDecision(getOwnerSupabaseClient(), {
			organizationId,
			requestId: result.request_id,
			version: parsed.data.version,
			decision: result.status,
			origin: env.APP_URL?.trim() || event.url.origin
		});
	return json({ ...result, emailed }, { headers: NO_STORE_HEADERS });
};
