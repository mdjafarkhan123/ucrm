import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	memberCostRateSchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

// What an employee costs per hour. Its own route rather than a field on the profile save: a name and a wage
// are not the same kind of fact, and the rate lives in its own table for exactly that reason — the profile is
// read by anyone who can see a teammate, this number is not.
//
// The change applies forward only. Every recorded hour already carries the rate it was recorded with, so
// nothing here reaches back and re-costs work that is already done.
export const PATCH: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json(
			{ error: 'The employee identifier is invalid.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}

	const parsed = memberCostRateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the hourly cost.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { auth } = required.context;
	const { data, error } = await event.locals.supabase.rpc('set_member_cost_rate', {
		target_organization_id: auth.organization.id,
		target_user_id: parsedUserId.data,
		// Null clears the rate, which the command stores as "not told yet". The generated argument type has no
		// way to say a Postgres parameter is nullable, so the cast says what the function's own comment says.
		new_cost_per_hour_minor: parsed.data.cost_per_hour_minor as number
	});
	if (error) {
		const status = error.code === 'P0404' ? 404 : error.code === '42501' ? 403 : 500;
		return json(
			{ error: error.message ?? 'That hourly cost could not be saved.' },
			{ status, headers: NO_STORE_HEADERS }
		);
	}

	return json(data, { headers: NO_STORE_HEADERS });
};
