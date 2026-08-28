import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';
import {
	communicationEmailSendingPauseSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

type PauseRow = {
	id: string;
	reason: string;
	engaged_by_owner_email: string;
	engaged_at: string;
};

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client
			.from('communication_email_sending_pauses')
			.select('id, scope, organization_id, reason, engaged_by_owner_email, engaged_at')
			.is('released_at', null)
			.or(`scope.eq.platform,organization_id.eq.${parsedOrganizationId.data}`);
		if (error) throw error;

		const rows = data ?? [];
		const platformRow = rows.find((row) => row.scope === 'platform') ?? null;
		const orgRow = rows.find((row) => row.scope === 'organization') ?? null;

		return json(
			{
				platform_paused: Boolean(platformRow),
				organization_pause: orgRow
					? ({
							id: orgRow.id,
							reason: orgRow.reason,
							engaged_by_owner_email: orgRow.engaged_by_owner_email,
							engaged_at: orgRow.engaged_at
						} satisfies PauseRow)
					: null
			},
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not load the organization email pause.', error);
		return json({ error: 'The organization email pause could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{
				error: 'The organization identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedOrganizationId.error)
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationEmailSendingPauseSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the pause details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { error } = await client.rpc('set_communication_email_organization_pause', {
			p_organization_id: parsedOrganizationId.data,
			p_engage: parsed.data.engage,
			p_reason: parsed.data.reason,
			p_actor_email: session.email
		});
		if (error) {
			if (error.code === '23503') {
				return json({ error: 'That organization was not found.' }, { status: 404 });
			}
			if (['23505', '23514'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		const { data: health, error: healthError } = await client.rpc(
			'get_communication_email_sending_health'
		);
		if (healthError) throw healthError;
		return json({ health }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not change the organization email pause.', error);
		return json({ error: 'The organization email pause could not be changed.' }, { status: 500 });
	}
};
