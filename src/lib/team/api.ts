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
