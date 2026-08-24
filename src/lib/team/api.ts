// The team, as anyone in it sees it: just names, for putting someone on a visit.
export type TeamMember = { id: string; full_name: string | null; avatar_url: string | null };

export const assignableTeamKey = ['team', 'assignable'] as const;

export async function fetchAssignableTeam(): Promise<TeamMember[]> {
	const response = await fetch('/api/team/assignable');
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'Your team could not be loaded.');
	}
	const result = (await response.json()) as { members: TeamMember[] };
	return result.members;
}

export type TeamMemberStatus = 'pending' | 'active' | 'deactivated';
export type TeamMemberRole = 'owner' | 'admin' | 'office' | 'sales' | 'field' | 'finance';

export type TeamDirectoryFilters = {
	search: string;
	status: TeamMemberStatus | '';
};

export type TeamDirectoryMember = {
	user_id: string;
	display_name: string | null;
	avatar_url: string | null;
	role: TeamMemberRole;
	status: TeamMemberStatus;
	access_revision: number;
	profile_revision: number;
	work_phone: string | null;
	job_title: string | null;
	schedule_color: string | null;
	created_at: string;
	deactivated_at: string | null;
	invitation: {
		id: string;
		email: string;
		state: 'reserving' | 'invited' | 'accepting';
		delivery_failed: boolean;
		last_sent_at: string | null;
		expires_at: string;
	} | null;
};

export type TeamDirectoryPage = {
	members: TeamDirectoryMember[];
	next_cursor: string | null;
	seats: { used: number; limit: number; is_unlimited: boolean };
};

export type TeamMemberDetail = TeamDirectoryMember;

export type TeamMemberProfileDraft = {
	full_name: string;
	work_phone: string;
	job_title: string;
	schedule_color: string;
	expected_profile_revision: number;
};

export type TeamAccessAdjustment = {
	control_id: string;
	override_state: 'grant' | 'deny';
};

export type TeamAccessControl = {
	id: string;
	label: string;
	example: string;
	included_in_role: boolean;
	effective: boolean;
	adjustment: 'grant' | 'deny' | null;
	available: boolean;
};

export type TeamAccessEditor = {
	member: {
		role: TeamMemberRole;
		status: TeamMemberStatus;
		access_revision: number;
		can_edit: boolean;
		cannot_edit_reason: string | null;
		is_adjusted: boolean;
	};
	roles: Array<{
		id: Exclude<TeamMemberRole, 'owner'>;
		label: string;
		summary: string;
		available: boolean;
		default_control_ids: string[];
	}>;
	capabilities: Array<{
		id: string;
		name: string;
		description: string;
		controls: TeamAccessControl[];
	}>;
};

export class TeamWriteError extends Error {
	stale: boolean;

	constructor(message: string, stale = false) {
		super(message);
		this.name = 'TeamWriteError';
		this.stale = stale;
	}
}

export class TeamInvitationWriteError extends Error {
	fieldErrors: Record<string, string>;
	code?: string;

	constructor(message: string, fieldErrors: Record<string, string> = {}, code?: string) {
		super(message);
		this.name = 'TeamInvitationWriteError';
		this.fieldErrors = fieldErrors;
		this.code = code;
	}
}

// Team responses describe what the signed-in manager may do. Keep the manager in every cache key so an
// Owner's editable response cannot be reused after the browser signs in as an Administrator.
export const teamDirectoryKey = (actorUserId: string, filters: TeamDirectoryFilters) =>
	['team', 'directory', actorUserId, filters] as const;
export const teamMemberKey = (actorUserId: string, userId: string) =>
	['team', 'member', actorUserId, userId] as const;
export const teamMemberAccessKey = (actorUserId: string, userId: string) =>
	['team', 'member', actorUserId, userId, 'access'] as const;

export async function createTeamInvitation(input: {
	email: string;
	role: Exclude<TeamMemberRole, 'owner'>;
}): Promise<{ invitationId: string; status: 'sent' | 'delivery_failed' }> {
	const response = await fetch('/api/team/invitations', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...input, permission_adjustments: [] })
	});
	const result = await response
		.json()
		.catch(() => ({}) as { error?: string; field_errors?: Record<string, string> });
	if (!response.ok) {
		throw new TeamInvitationWriteError(
			result.error ?? 'The invitation could not be sent.',
			result.field_errors ?? {}
		);
	}
	return result as { invitationId: string; status: 'sent' | 'delivery_failed' };
}

export async function resendTeamInvitation(
	invitationId: string
): Promise<{ status: 'sent' | 'delivery_failed' }> {
	const response = await fetch(`/api/team/invitations/${invitationId}/resend`, { method: 'POST' });
	const result = await response
		.json()
		.catch(() => ({}) as { error?: string; code?: string; status?: string });
	if (!response.ok) {
		throw new TeamInvitationWriteError(
			result.error ?? 'The invitation could not be resent.',
			{},
			result.code
		);
	}
	return result as { status: 'sent' | 'delivery_failed' };
}

export async function cancelTeamInvitation(invitationId: string): Promise<void> {
	const response = await fetch(`/api/team/invitations/${invitationId}/cancel`, { method: 'POST' });
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string; code?: string });
		throw new TeamInvitationWriteError(
			result.error ?? 'The invitation could not be cancelled.',
			{},
			result.code
		);
	}
}

export async function replaceTeamInvitationEmail(
	invitationId: string,
	email: string
): Promise<{ status: 'sent' | 'delivery_failed' }> {
	const response = await fetch(`/api/team/invitations/${invitationId}/replace-email`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ email })
	});
	const result = await response
		.json()
		.catch(() => ({}) as { error?: string; code?: string; field_errors?: Record<string, string> });
	if (!response.ok) {
		throw new TeamInvitationWriteError(
			result.error ?? 'The email could not be changed.',
			result.field_errors ?? {},
			result.code
		);
	}
	return result as { status: 'sent' | 'delivery_failed' };
}

export async function fetchTeamDirectory(
	filters: TeamDirectoryFilters,
	cursor?: string
): Promise<TeamDirectoryPage> {
	const params = new URLSearchParams();
	const search = filters.search.trim();
	if (search) params.set('search', search);
	if (filters.status) params.set('status', filters.status);
	if (cursor) params.set('cursor', cursor);

	const response = await fetch(`/api/team/members?${params.toString()}`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'Team members could not be loaded.');
	}
	return response.json();
}

export async function fetchTeamMember(userId: string): Promise<TeamMemberDetail> {
	const response = await fetch(`/api/team/members/${userId}`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'That team member could not be loaded.');
	}
	const result = (await response.json()) as { member: TeamMemberDetail };
	return result.member;
}

export async function saveTeamMemberProfile(
	userId: string,
	draft: TeamMemberProfileDraft
): Promise<void> {
	const response = await fetch(`/api/team/members/${userId}/profile`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(draft)
	});
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string; stale?: boolean });
		throw new TeamWriteError(
			result.error ?? 'Those member details could not be saved.',
			result.stale === true
		);
	}
}

export async function fetchTeamMemberAccess(userId: string): Promise<TeamAccessEditor> {
	const response = await fetch(`/api/team/members/${userId}/access`);
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw new Error(result.error ?? 'That person’s access could not be loaded.');
	}
	const result = (await response.json()) as { access: TeamAccessEditor };
	return result.access;
}

export async function saveTeamMemberRole(
	userId: string,
	draft: {
		role: Exclude<TeamMemberRole, 'owner'>;
		keep_adjustments: boolean;
		expected_access_revision: number;
	}
): Promise<void> {
	const response = await fetch(`/api/team/members/${userId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(draft)
	});
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string; stale?: boolean });
		throw new TeamWriteError(
			result.error ?? 'The employee role could not be changed.',
			result.stale === true
		);
	}
}

export async function saveTeamMemberAccess(
	userId: string,
	draft: { adjustments: TeamAccessAdjustment[]; expected_access_revision: number }
): Promise<void> {
	const response = await fetch(`/api/team/members/${userId}/permissions`, {
		method: 'PUT',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(draft)
	});
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string; stale?: boolean });
		throw new TeamWriteError(
			result.error ?? 'The permission adjustments could not be saved.',
			result.stale === true
		);
	}
}
