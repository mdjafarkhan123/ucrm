import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { freeAccessChangeSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const eventSelect =
	'id, organization_id, package_version_id, action, starts_at, access_until_date, target_grant_id, reason, actor_kind, actor_owner_email, occurred_at, created_at';

async function getFreeAccessState(client: ReturnType<typeof getOwnerSupabaseClient>, organizationId: string) {
	const [
		{ data: organization, error: organizationError },
		{ data: assignment, error: assignmentError },
		{ data: events, error: eventsError }
	] = await Promise.all([
		client.from('organizations').select('id, name').eq('id', organizationId).maybeSingle(),
		client
			.from('organization_package_assignments')
			.select('id, package_version_id')
			.eq('organization_id', organizationId)
			.order('effective_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(1)
			.maybeSingle(),
		client
			.from('organization_free_access_events')
			.select(eventSelect)
			.eq('organization_id', organizationId)
			.order('occurred_at', { ascending: false })
			.order('id', { ascending: false })
	]);

	if (organizationError) throw organizationError;
	if (assignmentError) throw assignmentError;
	if (eventsError) throw eventsError;
	if (!organization) return null;

	return {
		organization,
		has_package_assignment: assignment !== null,
		events: events ?? []
	};
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const state = await getFreeAccessState(client, parsedId.data);
		if (!state) return json({ error: 'Organization was not found.' }, { status: 404 });
		const access = await resolveOrganizationAccess(client, parsedId.data);
		return json({
			organization: state.organization,
			has_package_assignment: state.has_package_assignment,
			free_access: access.free_access,
			events: state.events
		});
	} catch (error) {
		console.error('Could not load organization free access.', error);
		return json({ error: 'Free access could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsed = freeAccessChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the free access change.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	const grantsForeverAccess =
		parsed.data.action === 'convert_to_forever' ||
		((parsed.data.action === 'grant' || parsed.data.action === 'extend') &&
			!parsed.data.access_until_date);
	if (grantsForeverAccess && !consumeOwnerStepUp(event, session)) {
		return json(
			{
				error: 'Confirm your password before granting permanent free access.',
				step_up_required: true
			},
			{ status: 403 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedId.data;
		const { data: command, error } = await client.rpc('apply_organization_free_access_change', {
			target_organization_id: organizationId,
			target_action: parsed.data.action,
			target_grant_id: (parsed.data.action === 'grant' ? null : parsed.data.grant_id) as string,
			target_starts_at: (parsed.data.action === 'grant' ? parsed.data.starts_at : null) as string,
			target_access_until_date: (parsed.data.action === 'grant' || parsed.data.action === 'extend'
				? (parsed.data.access_until_date ?? null)
				: null) as string,
			idempotency_key: parsed.data.idempotency_key,
			private_reason: parsed.data.reason,
			actor_owner_email: session.email
		});
		if (error) {
			if (['23503', '23505', '23514', '40001'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		const state = await getFreeAccessState(client, organizationId);
		if (!state) return json({ error: 'Organization was not found.' }, { status: 404 });
		const access = await resolveOrganizationAccess(client, organizationId);
		return json({
			command,
			organization: state.organization,
			has_package_assignment: state.has_package_assignment,
			free_access: access.free_access,
			events: state.events
		});
	} catch (error) {
		console.error('Could not change organization free access.', error);
		return json({ error: 'Free access could not be changed.' }, { status: 500 });
	}
};
