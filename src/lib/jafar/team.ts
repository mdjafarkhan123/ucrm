import type { TeamRole } from '$lib/jafar/team-access';

// D1: the Team & access page's calls (ADR 0008). Only the platform owner can make them.

export type TeamMember = {
	id: string;
	email: string;
	full_name: string | null;
	role: TeamRole;
	status: 'invited' | 'active';
	invited_at: string;
	invitation_expires_at: string | null;
	accepted_at: string | null;
	invited_by_email: string;
};

export class TeamRequestError extends Error {
	constructor(
		message: string,
		readonly fieldErrors: Record<string, string> = {},
		/** The invitation is saved but its email did not go out. */
		readonly emailFailed = false
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
			result.code === 'email_failed'
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
