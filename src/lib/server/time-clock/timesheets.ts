import { json, type RequestEvent } from '@sveltejs/kit';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import {
	permissionIsEnabled,
	resolveOrganizationAccess,
	type EffectiveOrganizationAccess
} from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';

export type TimesheetReader =
	| {
			auth: OrganizationContext;
			access: EffectiveOrganizationAccess;
			teamVisible: boolean;
			/** May add and correct their own hours (time.track_own), not only start and stop timers. */
			recordsOwn: boolean;
	  }
	| { response: Response };

// Timesheets open to anyone who times or records hours: their own (they see only themselves) or the team's
// (they see everyone). Someone who only starts and stops their own timers (time.timers_own) reads their own
// hours here and is refused every change by `requireTimesheetWriter`. The same two answers `requireOrganizationPermission` gives, told apart the same way: the plan
// does not include time tracking, or this member records no hours. The database repeats the who-sees-whom
// rule, so this is the clear refusal rather than the only one.
export async function requireTimesheetReader(event: RequestEvent): Promise<TimesheetReader> {
	const auth = await getOrganizationContext(event);
	if (!auth) {
		return {
			response: json(
				{ error: 'Authentication or organization membership required.' },
				{ status: 401 }
			)
		};
	}

	try {
		const access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);

		if (!permissionIsEnabled('time.track_own', access.features)) {
			return {
				response: json(
					{ error: 'This is not part of your current plan.', reason: 'feature_unavailable' },
					{ status: 403 }
				)
			};
		}

		const teamVisible = hasPermission(access, 'time.track_team');
		const recordsOwn = teamVisible || hasPermission(access, 'time.track_own');
		if (!recordsOwn && !hasPermission(access, 'time.timers_own')) {
			return {
				response: json(
					{ error: 'You do not have access to do that.', reason: 'permission_denied' },
					{ status: 403 }
				)
			};
		}

		return { auth, access, teamVisible, recordsOwn };
	} catch (error) {
		console.error('Could not resolve organization access.', error);
		return { response: json({ error: 'Access could not be verified.' }, { status: 500 }) };
	}
}

// Adding, correcting or deleting hours, and changing or stopping a timer at a chosen time: a reader who only
// starts and stops their own timers is refused here, before the database refuses the same (plan §
// Permissions). Whose hours they are is still checked by each route and by the command.
export async function requireTimesheetWriter(event: RequestEvent): Promise<TimesheetReader> {
	const check = await requireTimesheetReader(event);
	if ('response' in check || check.recordsOwn) return check;
	return {
		response: json(
			{ error: 'Ask a manager to change your hours.', reason: 'permission_denied' },
			{ status: 403 }
		)
	};
}
