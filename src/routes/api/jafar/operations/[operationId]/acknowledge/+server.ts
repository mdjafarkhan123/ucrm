import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { operationIdSchema } from '$lib/server/validation/operation.schema';

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = operationIdSchema.safeParse(event.params.operationId);
	if (!parsedId.success)
		return json({ error: 'The operation identifier is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();

	try {
		const { data: attempt, error: attemptError } = await client
			.from('platform_operation_attempts')
			.select('status')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (attemptError) throw attemptError;
		if (!attempt) return json({ error: 'Operation was not found.' }, { status: 404 });
		if (attempt.status === 'succeeded' || attempt.status === 'manually_resolved')
			return json({ error: 'This operation is already closed.' }, { status: 409 });

		const { error } = await client
			.from('platform_operation_attempts')
			.update({
				status: 'acknowledged',
				acknowledged_at: new Date().toISOString(),
				acknowledged_by_owner_email: session.email
			})
			.eq('id', parsedId.data);
		if (error) throw error;

		return json({ ok: true });
	} catch (error) {
		console.error('Could not acknowledge the operation.', error);
		return json({ error: 'The operation could not be acknowledged.' }, { status: 500 });
	}
};
