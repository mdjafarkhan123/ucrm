import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	followLaunchDecision,
	launchApprovalTokenHash,
	launchLinkIpBucketKey,
	launchLinkTokenBucketKey
} from '$lib/server/setup/launch-approval';
import { setupLaunchLinkDecisionSchema } from '$lib/server/validation/setup.schema';

// Client onboarding E4 (plan §6): the approver's answer through their private link — Approve, or Not yet with an
// optional note. The link is the proof of who they are, as with an emailed signing link; which request, which
// version and whether an answer is still allowed are decided inside the database command.

const UNAVAILABLE = 'This link is no longer available. Ask Uplift for a new one.';
const NO_STORE = { 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' };

// A public write with no session behind it, so both limits are low, as the quote link's are.
const DECISION_LIMIT = { windowSeconds: 300, maxAttempts: 8 };
const DECISION_TOKEN_LIMIT = { windowSeconds: 300, maxAttempts: 5 };

type DecisionResult = {
	status: 'approved' | 'not_yet' | 'already_approved';
	request_id: string;
	organization_id?: string;
	version?: number;
};

export const POST: RequestHandler = async (event) => {
	const tokenHash = launchApprovalTokenHash(event.params.token);
	if (!tokenHash) return json({ error: UNAVAILABLE }, { status: 410, headers: NO_STORE });

	const client = getOwnerSupabaseClient();
	const address = event.getClientAddress();
	const [byAddress, byToken] = await Promise.all([
		checkRateLimit(client, {
			bucketKey: launchLinkIpBucketKey('decision', address),
			...DECISION_LIMIT
		}),
		checkRateLimit(client, {
			bucketKey: launchLinkTokenBucketKey('decision', tokenHash),
			...DECISION_TOKEN_LIMIT
		})
	]);
	if (!byAddress.allowed) return rateLimitedResponse(byAddress.retryAfterSeconds);
	if (!byToken.allowed) return rateLimitedResponse(byToken.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'We could not read that. Please try again.' }, { status: 400 });
	}
	const parsed = setupLaunchLinkDecisionSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{ error: parsed.error.issues[0]?.message ?? 'Please check your answer.' },
			{ status: 422, headers: NO_STORE }
		);

	const { data, error } = await client.rpc('decide_setup_launch_link', {
		supplied_token_hash: tokenHash,
		decision: parsed.data.decision,
		note: parsed.data.note ?? undefined
	});
	if (error) {
		if (error.code === '23514')
			return json({ error: error.message }, { status: 422, headers: NO_STORE });
		console.error('Could not record the launch decision.');
		return json(
			{ error: 'We could not save that. Please try again.' },
			{ status: 500, headers: NO_STORE }
		);
	}
	if (!data) return json({ error: UNAVAILABLE }, { status: 410, headers: NO_STORE });

	const result = data as unknown as DecisionResult;
	if ((result.status === 'approved' || result.status === 'not_yet') && result.organization_id)
		await followLaunchDecision(client, {
			organizationId: result.organization_id,
			requestId: result.request_id,
			version: result.version ?? 0,
			decision: result.status,
			origin: env.APP_URL?.trim() || event.url.origin
		});
	return json({ status: result.status }, { headers: NO_STORE });
};
