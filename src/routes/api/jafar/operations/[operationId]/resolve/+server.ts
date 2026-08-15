import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	operationIdSchema,
	operationResolveSchema
} from '$lib/server/validation/operation.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = operationIdSchema.safeParse(event.params.operationId);
	if (!parsedId.success)
		return json({ error: 'The operation identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = operationResolveSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{ error: 'Enter a resolution note.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);

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
				status: 'manually_resolved',
				resolved_at: new Date().toISOString(),
				resolved_by_owner_email: session.email,
				resolution_note: parsed.data.note
			})
			.eq('id', parsedId.data);
		if (error) throw error;

		return json({ ok: true });
	} catch (error) {
		console.error('Could not resolve the operation.', error);
		return json({ error: 'The operation could not be resolved.' }, { status: 500 });
	}
};
