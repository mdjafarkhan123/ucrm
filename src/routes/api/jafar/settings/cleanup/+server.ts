import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationEarlyPurgeSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

function stepUpRequired() {
	return json(
		{
			error: 'Confirm your password before permanently deleting this organization.',
			step_up_required: true
		},
		{ status: 403 }
	);
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client
			.from('organization_closure_records')
			.select('id, organization_id, reason, started_at, deadline_at, organizations(name, slug)')
			.eq('status', 'pending_closure')
			.order('deadline_at', { ascending: true });
		if (error) throw error;

		return json({ closing_organizations: data ?? [] });
	} catch (error) {
		console.error('Could not load the cleanup queue.', error);
		return json({ error: 'The cleanup queue could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = organizationEarlyPurgeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the delete confirmation.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) return stepUpRequired();

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsed.data.organization_id;

		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name')
			.eq('id', organizationId)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		if (parsed.data.typed_organization_name !== organization.name) {
			return json(
				{
					error: 'The typed organization name does not match.',
					field_errors: { typed_organization_name: 'Type the organization name exactly to confirm.' }
				},
				{ status: 422 }
			);
		}

		const { data: result, error } = await client.rpc('apply_organization_purge', {
			target_organization_id: organizationId,
			purge_trigger_kind: 'early_manual',
			actor_owner_email: session.email
		});
		if (error) throw error;

		const applied = result as { applied: boolean; reason?: string; operation_id?: string } | null;
		if (!applied?.applied) {
			return json({ error: 'This organization was already deleted.' }, { status: 409 });
		}

		return json({ operation_id: applied.operation_id, purged: true });
	} catch (error) {
		console.error('Could not permanently delete the organization.', error);
		return json({ error: 'The organization could not be permanently deleted.' }, { status: 500 });
	}
};
