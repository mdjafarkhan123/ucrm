import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, notFound, validationError } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { LEAD_NOT_FOUND, readBody } from '$lib/server/jafar/lead-approval';
import { dealCommandResponse } from '$lib/server/jafar/deals';
import { setupOwnerSchema } from '$lib/server/validation/deal.schema';
import {
	TEAM_ROLES,
	effectiveTeamAccess,
	storedTeamAccessAdjustments,
	type TeamRole
} from '$lib/jafar/team-access';
import type { SetupOwnerChoice } from '$lib/jafar/deals';

// Jafar business management B5: who looks after a new client's setup -- Jafar by default, or a teammate who can
// open Onboarding. Choosing is Jafar's alone; the change is written to the business's history.

type Client = ReturnType<typeof getOwnerSupabaseClient>;

/** Active teammates whose access opens Onboarding, by name. */
async function setupOwnerChoices(client: Client): Promise<SetupOwnerChoice[]> {
	const { data, error } = await client
		.from('platform_team_members')
		.select('id, email, full_name, avatar_url, role, area_adjustments, action_grants')
		.eq('status', 'active')
		.is('removed_at', null);
	if (error) throw error;
	return (data ?? [])
		.filter((member) => {
			if (!TEAM_ROLES.includes(member.role as TeamRole)) return false;
			const access = effectiveTeamAccess(
				member.role as TeamRole,
				storedTeamAccessAdjustments(member.area_adjustments, member.action_grants)
			);
			return Boolean(access.areas.onboarding);
		})
		.map((member) => ({
			id: member.id,
			name: member.full_name || member.email,
			avatar_url: member.avatar_url
		}))
		.sort((a, b) => a.name.localeCompare(b.name));
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();

	try {
		return json(
			{ choices: await setupOwnerChoices(getOwnerSupabaseClient()) },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not list who can look after setup.', error);
		return json({ error: 'Your team could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session || session.role !== null) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	const body = await readBody(event.request, setupOwnerSchema);
	if ('response' in body) return body.response;

	const client = getOwnerSupabaseClient();
	const memberId = body.data.member_id;
	if (memberId !== null) {
		try {
			const choices = await setupOwnerChoices(client);
			if (!choices.some((choice) => choice.id === memberId)) {
				return validationError(
					{ member_id: 'That teammate cannot open Onboarding. Change their access first.' },
					409
				);
			}
		} catch (error) {
			console.error('Could not check who can look after setup.', error);
			return json({ error: 'Your team could not be loaded.' }, { status: 500 });
		}
	}

	const result = await client.rpc('owner_business_set_setup_owner', {
		actor_email: session.email,
		target_relationship_id: event.params.id,
		// Null hands setup back to Jafar; the generated types do not show the parameter can be null.
		target_member_id: memberId as string
	});
	return dealCommandResponse(result, 'change who looks after setup', LEAD_NOT_FOUND);
};
