import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { SetupState } from '$lib/server/setup/read';
import { projectView, type ProjectView } from '$lib/setup/project-state';
import { todayIn } from '$lib/setup/ready';

/**
 * Client onboarding E1: the client's step tracker (plan §5). Besides what the setup read already holds, it needs
 * the day the account was created — which follows Jafar's confirmation of the payment — and the first send: two
 * single-row reads keyed by the organization. Null when either read fails.
 */
export async function readSetupProject(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	state: SetupState,
	returnedCount: number
): Promise<ProjectView | null> {
	const [organization, firstSend] = await Promise.all([
		supabase.from('organizations').select('created_at').eq('id', organizationId).maybeSingle(),
		state.sent && state.sent.number > 1
			? supabase
					.from('organization_setup_submissions')
					.select('submitted_at')
					.eq('organization_id', organizationId)
					.eq('submission_number', 1)
					.maybeSingle()
			: Promise.resolve({ data: state.sent, error: null })
	]);
	if (organization.error || firstSend.error) return null;

	return projectView({
		paid_at: organization.data?.created_at ?? null,
		first_sent_at: firstSend.data?.submitted_at ?? null,
		sent: state.sent,
		returned_count: returnedCount,
		ready: state.ready,
		// Only Ready's dates depend on the day, and they were counted in the zone Ready recorded.
		today: todayIn(state.ready?.time_zone ?? 'UTC')
	});
}
