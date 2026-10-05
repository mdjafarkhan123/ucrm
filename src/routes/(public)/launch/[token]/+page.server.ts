import type { PageServerLoad } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { launchApprovalTokenHash } from '$lib/server/setup/launch-approval';
import type { LaunchLinkDocument } from '$lib/setup/launch-approval';

// Client onboarding E4 (plan §6): the final approver's private link. Like the quote and receipt links, the token
// from the URL is hashed here and the hash goes to the one function the service role may call, which decides what
// the page shows: the business, the preview's cards, and whether it is still waiting or already approved.
//
// Every way of failing looks the same — unknown, replaced by a newer link, cancelled, expired — so the page cannot
// be used to learn whether a client exists. Loading the page records nothing; mail scanners open links first.
export const load: PageServerLoad = async ({ params, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const tokenHash = launchApprovalTokenHash(params.token);
	if (!tokenHash) return { document: null };

	const { data, error } = await getOwnerSupabaseClient().rpc('resolve_setup_launch_link', {
		supplied_token_hash: tokenHash
	});
	// Not logged with the token: a failure here is a broken link or a guess.
	if (error || !data) return { document: null };
	return { document: data as unknown as LaunchLinkDocument };
};
