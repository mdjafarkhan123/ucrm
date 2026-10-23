import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import {
	createTollfreeCheckDeps,
	sendTollfreeCheck,
	TollfreeCheckError
} from '$lib/server/communications/sms-tollfree-verification';
import { tollfreeProofs, tollfreeProofUrl } from '$lib/server/communications/sms-tollfree-proof';
import { smsTollfreeAnswersSchema } from '$lib/server/validation/communications-sms-tollfree.schema';

const bodySchema = z.object({ expected_revision: z.number().int().min(1) });

export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in auth) return auth.response;
	const senderId = z.uuid().safeParse(event.params.senderId);
	if (!senderId.success) return json({ error: 'Number not found.' }, { status: 404 });
	const parsed = bodySchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) return json({ error: 'Reload this check and try again.' }, { status: 422 });
	const organizationId = auth.auth.organization.id;
	const client = getOwnerSupabaseClient();
	const { data: check, error } = await client
		.from('communication_sms_tollfree_verifications')
		.select('id, answers, revision, status')
		.eq('organization_id', organizationId)
		.eq('sender_identity_id', senderId.data)
		.maybeSingle();
	if (error) return databaseError();
	if (!check) return json({ error: 'Start this check first.' }, { status: 404 });
	if (
		check.revision !== parsed.data.expected_revision ||
		!['draft', 'needs_fix'].includes(check.status)
	)
		return json({ error: 'This check changed elsewhere. Reload it first.' }, { status: 409 });
	let proofs;
	try {
		proofs = await tollfreeProofs(client, organizationId, check.id);
	} catch {
		return databaseError();
	}
	let urls: string[];
	try {
		urls = proofs.map((picture) => tollfreeProofUrl(picture.public_token));
	} catch {
		return json(
			{ error: 'Uplift needs a public HTTPS address before this can be sent.' },
			{ status: 503 }
		);
	}
	const business =
		check.answers && typeof check.answers === 'object' && !Array.isArray(check.answers)
			? check.answers.business
			: null;
	const answers = smsTollfreeAnswersSchema.safeParse({ business, opt_in_image_urls: urls });
	if (!answers.success) {
		return json(
			{
				error: 'Complete the business, texting and picture steps before sending.',
				field_errors: answers.error.issues.map((issue) => ({
					field: issue.path.join('.'),
					message: issue.message
				}))
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}
	// Refresh the server-owned picture links immediately before the claim. The revision remains the same:
	// picture additions/removals already raised it, and user answers cannot forge these links.
	const { error: saveError } = await client
		.from('communication_sms_tollfree_verifications')
		.update({ answers: answers.data })
		.eq('organization_id', organizationId)
		.eq('id', check.id)
		.eq('revision', check.revision)
		.in('status', ['draft', 'needs_fix']);
	if (saveError) return databaseError();
	try {
		const outcome = await sendTollfreeCheck(createTollfreeCheckDeps(), {
			organizationId,
			verificationId: check.id,
			expectedRevision: check.revision,
			actorUserId: auth.auth.user.id
		});
		return json(outcome, { headers: NO_STORE_HEADERS });
	} catch (cause) {
		if (cause instanceof TollfreeCheckError)
			return json(
				{ error: cause.message, code: cause.code },
				{ status: cause.code === 'not_sendable' ? 409 : 503, headers: NO_STORE_HEADERS }
			);
		console.error('Could not send toll-free check.', cause);
		return databaseError();
	}
};
