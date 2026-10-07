import { z } from 'zod';
import type { RequestHandler } from './$types';
import { notFound } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { LEAD_NOT_FOUND, approvalResponse, readBody } from '$lib/server/jafar/lead-approval';
import { leadApprovalSchema } from '$lib/server/validation/lead.schema';

// Jafar business management B3: approve exactly these contact details for first contact. The Lead becomes
// Approved and its next action becomes the first-contact task. Nothing is sent. Needs "Approve who to contact".

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const body = await readBody(event.request, leadApprovalSchema);
	if ('response' in body) return body.response;

	const result = await getOwnerSupabaseClient().rpc('owner_lead_approve', {
		actor_email: session.email,
		target_id: event.params.id,
		method_ids: body.data.method_ids,
		whatsapp_permission_ids: body.data.whatsapp_permission_ids,
		task_due_on: body.data.due_on
	});
	return approvalResponse(result, 'approve the Lead');
};
