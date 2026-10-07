import type { PageServerLoad } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { inspectTeamInvitation } from '$lib/server/jafar/team-members';
import { TEAM_ROLE_LABELS } from '$lib/jafar/team-access';

// The invitation link a teammate opens from their email (D1, ADR 0008). The link's secret never leaves this
// page: no caching, no referrer, no indexing.
export const load: PageServerLoad = async ({ url, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const token = url.searchParams.get('token')?.trim() ?? '';
	if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return { invitation: null };

	try {
		const invitation = await inspectTeamInvitation(getOwnerSupabaseClient(), token);
		if (!invitation.valid) return { invitation: null };
		return {
			invitation: { emailHint: invitation.emailHint, roleLabel: TEAM_ROLE_LABELS[invitation.role] }
		};
	} catch (error) {
		console.error('A team invitation could not be checked.', error);
		return { invitation: null };
	}
};
