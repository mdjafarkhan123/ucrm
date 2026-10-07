import {
	JAFAR_AREAS,
	JAFAR_AREA_LABELS,
	SENSITIVE_ACTIONS,
	SENSITIVE_ACTION_DETAILS,
	TEAM_ROLES,
	TEAM_ROLE_LABELS,
	effectiveTeamAccess,
	storedTeamAccessAdjustments,
	type AreaSetting,
	type TeamAccess,
	type TeamAccessAdjustments,
	type TeamRole
} from '$lib/jafar/team-access';
import type { Json } from '$lib/database.types';

// The Team & access page's calls (D1, D2, ADR 0008). Only the platform owner can make them.

export type TeamMember = {
	id: string;
	email: string;
	full_name: string | null;
	avatar_url: string | null;
	role: TeamRole;
	status: 'invited' | 'active';
	invited_at: string;
	invitation_expires_at: string | null;
	accepted_at: string | null;
	invited_by_email: string;
};

/** One event in a teammate's history: invited, resent, access changed, removed. */
export type TeamAccessHistoryEntry = {
	id: string;
	event_type: string;
	actor_email: string;
	created_at: string;
	before_state: Json | null;
	after_state: Json | null;
};

export type TeamMemberAccessView = {
	member: {
		id: string;
		email: string;
		full_name: string | null;
		role: TeamRole;
		status: 'invited' | 'active';
		access_revision: number;
	};
	adjustments: TeamAccessAdjustments;
	access: TeamAccess;
	history: TeamAccessHistoryEntry[];
};

export class TeamRequestError extends Error {
	constructor(
		message: string,
		readonly fieldErrors: Record<string, string> = {},
		/** The invitation is saved but its email did not go out. */
		readonly emailFailed = false,
		/** Someone saved a newer version since this one was loaded. */
		readonly stale = false
	) {
		super(message);
	}
}

async function send<T>(input: string, init: RequestInit, fallback: string): Promise<T> {
	const response = await fetch(input, init);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new TeamRequestError(
			result.error ?? fallback,
			result.field_errors ?? {},
			result.code === 'email_failed',
			result.code === 'stale'
		);
	}
	return result as T;
}

export async function fetchTeam(): Promise<TeamMember[]> {
	const result = await send<{ members: TeamMember[] }>(
		'/api/jafar/team',
		{},
		'Your team could not be loaded.'
	);
	return result.members;
}

export function inviteTeammate(input: { email: string; role: TeamRole }) {
	return send<{ member: TeamMember }>(
		'/api/jafar/team',
		{
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(input)
		},
		'The invitation could not be sent.'
	);
}

export function resendTeamInvitation(memberId: string) {
	return send<{ member: TeamMember }>(
		`/api/jafar/team/${memberId}/resend`,
		{ method: 'POST' },
		'The invitation could not be resent.'
	);
}

export function removeTeammate(memberId: string) {
	return send<{ ok: true }>(
		`/api/jafar/team/${memberId}`,
		{ method: 'DELETE' },
		'The teammate could not be removed.'
	);
}

export function fetchTeamMemberAccess(memberId: string) {
	return send<TeamMemberAccessView>(
		`/api/jafar/team/${memberId}/access`,
		{},
		'This teammate’s access could not be loaded.'
	);
}

export function saveTeamMemberAccess(
	memberId: string,
	input: {
		role: TeamRole;
		areas: TeamAccess['areas'];
		actions: TeamAccess['actions'];
		expected_access_revision: number;
	}
) {
	return send<TeamMemberAccessView>(
		`/api/jafar/team/${memberId}/access`,
		{
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(input)
		},
		'The access could not be saved.'
	);
}

const AREA_SETTING_WORDS: Record<AreaSetting, string> = {
	none: 'off',
	look: 'view only',
	work: 'can change'
};

function stateAccess(state: Json | null): { role: TeamRole; access: TeamAccess } | null {
	if (!state || typeof state !== 'object' || Array.isArray(state)) return null;
	const role = state.role;
	if (typeof role !== 'string' || !(TEAM_ROLES as readonly string[]).includes(role)) return null;
	const grants = Array.isArray(state.action_grants)
		? state.action_grants.filter((grant): grant is string => typeof grant === 'string')
		: [];
	const adjustments = storedTeamAccessAdjustments(state.area_adjustments, grants);
	return { role: role as TeamRole, access: effectiveTeamAccess(role as TeamRole, adjustments) };
}

/** What one history event did, in short sentences for Jafar. */
export function describeTeamHistoryEntry(entry: TeamAccessHistoryEntry): string[] {
	switch (entry.event_type) {
		case 'team_member_invited': {
			const after = entry.after_state as { role?: string } | null;
			const role = TEAM_ROLE_LABELS[after?.role as TeamRole];
			return [role ? `Invited as ${role}` : 'Invited'];
		}
		case 'team_invitation_resent':
			return ['Invitation sent again'];
		case 'team_invitation_cancelled':
			return ['Invitation cancelled'];
		case 'team_member_removed':
			return ['Removed from the team and signed out'];
		case 'team_access_changed':
			break;
		default:
			return ['Changed'];
	}

	const before = stateAccess(entry.before_state);
	const after = stateAccess(entry.after_state);
	if (!before || !after) return ['Access changed'];

	const lines: string[] = [];
	if (before.role !== after.role) {
		lines.push(`Role: ${TEAM_ROLE_LABELS[before.role]} → ${TEAM_ROLE_LABELS[after.role]}`);
	}
	for (const area of JAFAR_AREAS) {
		const from = before.access.areas[area] ?? 'none';
		const to = after.access.areas[area] ?? 'none';
		if (from !== to) {
			lines.push(
				`${JAFAR_AREA_LABELS[area]}: ${AREA_SETTING_WORDS[from]} → ${AREA_SETTING_WORDS[to]}`
			);
		}
	}
	for (const action of SENSITIVE_ACTIONS) {
		const had = before.access.actions.includes(action);
		const has = after.access.actions.includes(action);
		if (had !== has) {
			lines.push(`${has ? 'Turned on' : 'Turned off'}: ${SENSITIVE_ACTION_DETAILS[action].label}`);
		}
	}
	return lines.length ? lines : ['Saved with no change'];
}
