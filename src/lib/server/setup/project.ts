import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { SetupState } from '$lib/server/setup/read';
import { projectView, type ProjectView } from '$lib/setup/project-state';
import { todayIn } from '$lib/setup/ready';

/**
 * Client onboarding E1: the client's step tracker (plan §5). Besides what the setup read already holds, it needs
 * the day the account was created — which follows Jafar's confirmation of the payment — the first send, and after
 * Ready the newest released preview (E3) and the standing launch approval (E4): single-row reads keyed by the
 * organization. Null when one fails.
 */
export async function readSetupProject(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	state: SetupState,
	returnedCount: number
): Promise<ProjectView | null> {
	const [organization, firstSend, preview, approval] = await Promise.all([
		supabase.from('organizations').select('created_at').eq('id', organizationId).maybeSingle(),
		state.sent && state.sent.number > 1
			? supabase
					.from('organization_setup_submissions')
					.select('submitted_at')
					.eq('organization_id', organizationId)
					.eq('submission_number', 1)
					.maybeSingle()
			: Promise.resolve({ data: state.sent, error: null }),
		state.ready
			? supabase
					.from('organization_setup_previews')
					.select('version, released_at, notes_sent_at')
					.eq('organization_id', organizationId)
					.not('released_at', 'is', null)
					.order('version', { ascending: false })
					.limit(1)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null }),
		state.ready
			? supabase
					.from('organization_setup_launch_approvals')
					.select('version, approved_at')
					.eq('organization_id', organizationId)
					.eq('status', 'approved')
					.is('replaced_at', null)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null })
	]);
	if (organization.error || firstSend.error || preview.error || approval.error) return null;

	return projectView({
		paid_at: organization.data?.created_at ?? null,
		first_sent_at: firstSend.data?.submitted_at ?? null,
		sent: state.sent,
		returned_count: returnedCount,
		ready: state.ready,
		preview: preview.data?.released_at
			? {
					version: preview.data.version,
					released_at: preview.data.released_at,
					notes_sent_at: preview.data.notes_sent_at
				}
			: null,
		approval: approval.data?.approved_at
			? { version: approval.data.version, approved_at: approval.data.approved_at }
			: null,
		// Only Ready's dates depend on the day, and they were counted in the zone Ready recorded.
		today: todayIn(state.ready?.time_zone ?? 'UTC')
	});
}
