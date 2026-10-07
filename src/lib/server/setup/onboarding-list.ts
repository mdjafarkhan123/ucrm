import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { SetupCatalogue } from '$lib/setup/catalogue';
import type { OnboardingClient } from '$lib/setup/onboarding-list';
import { projectState } from '$lib/setup/project-state';
import { todayIn } from '$lib/setup/ready';

// Jafar's onboarding rows as `owner_client_onboarding_list` returns them, finished on the server: the next
// section's title in the published setup version and the client-facing project state. Shared by the onboarding
// list (client onboarding C1) and the Client box on a business's page (Jafar business B5).

export type RawOnboardingClient = Omit<OnboardingClient, 'next_section_title' | 'project_state'>;

/** Null when the Ready for Uplift dates could not be read. */
export async function presentOnboardingRows(
	client: SupabaseClient<Database>,
	catalogue: SetupCatalogue,
	rows: RawOnboardingClient[]
): Promise<OnboardingClient[] | null> {
	// E1: Ready turns into Building on the client's first business day after it, so each Ready client's start date
	// and time zone are needed — one primary-key read for at most a page of clients.
	const readyIds = rows.filter((row) => row.ready_at).map((row) => row.id);
	const readyRows = new Map<
		string,
		{ submission_number: number; start_date: string; time_zone: string }
	>();
	if (readyIds.length > 0) {
		const ready = await client
			.from('organization_setup_ready')
			.select('organization_id, submission_number, start_date, time_zone')
			.in('organization_id', readyIds);
		if (ready.error) {
			console.error('Could not read Ready for Uplift dates.', ready.error);
			return null;
		}
		for (const row of ready.data) readyRows.set(row.organization_id, row);
	}

	return rows.map((row) => {
		const ready = readyRows.get(row.id);
		return {
			...row,
			next_section_title:
				catalogue.sections.find((section) => section.key === row.next_section_key)?.title ?? null,
			project_state: projectState({
				paid_at: row.account_created_at,
				first_sent_at: null,
				sent:
					row.sent_number && row.sent_at
						? { number: row.sent_number, submitted_at: row.sent_at }
						: null,
				returned_count: row.returned_count,
				ready:
					ready && row.target_from && row.target_to
						? {
								submission_number: ready.submission_number,
								start_date: ready.start_date,
								target_from: row.target_from,
								target_to: row.target_to
							}
						: null,
				preview:
					row.preview_version && row.preview_released_at
						? {
								version: row.preview_version,
								released_at: row.preview_released_at,
								notes_sent_at: row.preview_sent_at
							}
						: null,
				approval:
					row.approval_status === 'approved' && row.approval_version && row.approved_at
						? { version: row.approval_version, approved_at: row.approved_at }
						: null,
				handover: { live_at: row.live_at, delivered_at: row.delivered_at },
				today: todayIn(ready?.time_zone ?? 'UTC')
			})
		};
	});
}
