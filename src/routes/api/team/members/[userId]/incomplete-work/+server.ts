import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { userIdSchema } from '$lib/server/validation/access.schema';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';

// Mirrors get_incomplete_assignments_for_member's shape exactly, so a drift between the two is caught here
// instead of surfacing as a blank confirmation dialog.
const incompleteWorkSchema = z.object({
	assessments: z.array(z.object({ id: z.uuid(), starts_at: z.string().nullable() })),
	assessments_total: z.number().int().nonnegative(),
	visits: z.array(
		z.object({
			id: z.uuid(),
			visit_date: z.string().nullable(),
			start_time: z.string().nullable(),
			title: z.string().nullable()
		})
	),
	visits_total: z.number().int().nonnegative(),
	tasks: z.array(z.object({ id: z.uuid(), title: z.string(), due_on: z.string().nullable() })),
	tasks_total: z.number().int().nonnegative()
});

export type IncompleteWork = z.infer<typeof incompleteWorkSchema>;

// What the Deactivate confirmation names before a manager confirms. Only fetched when that dialog is about
// to open -- it is not part of the member detail page's own load.
export const GET: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json(
			{ error: 'The employee identifier is invalid.' },
			{ status: 422, headers: PRIVATE_READ_HEADERS }
		);
	}

	const { data, error } = await event.locals.supabase.rpc('get_incomplete_assignments_for_member', {
		target_organization_id: required.context.auth.organization.id,
		target_user_id: parsedUserId.data
	});

	const parsed = incompleteWorkSchema.safeParse(data);
	if (error || !parsed.success) {
		console.error('Could not load incomplete assignments for a team member.', error);
		return json(
			{ error: 'Their open work could not be loaded.' },
			{ status: 500, headers: PRIVATE_READ_HEADERS }
		);
	}

	return json({ assignments: parsed.data }, { headers: PRIVATE_READ_HEADERS });
};
