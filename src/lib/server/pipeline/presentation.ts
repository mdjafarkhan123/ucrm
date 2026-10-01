import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { DEFAULT_INACTIVITY_DAYS, type InactivityDays } from '$lib/pipeline/freshness';

// Whether this organization shows the collapsed five-column board or the seven-column detailed one, and how
// many quiet days each built-in stage allows before its cards warn. Both are presentation and nothing else:
// no stage, transition, history or report reads them.
//
// Read fresh every time, never cached the way `organizationFormatting` caches the timezone. Turning the
// toggle on has to show up on the board straight away, and an in-process cache would leave whoever saved
// it — or a teammate on another server — looking at the old board for minutes with nothing visibly wrong.
// This is one primary-key row, asked alongside the counts rather than before them, so it costs the board
// nothing.
//
// The owner's inactivity days ride on the same row for the same reason: the board needs them as soon as a
// card can warn, and a stale copy would warn on the wrong day.
export type PipelinePresentation = {
	detailed_assessment_stages: boolean;
	inactivity_days: InactivityDays;
};

export type PipelinePresentationLookup =
	{ ok: true; presentation: PipelinePresentation } | { ok: false; presentation: null };

// Read with the server's own client for the same reason as `organizationFormatting`: a Pipeline viewer
// denied settings.business.view must still see their organization's board, not the default one. The
// caller has already checked pipeline.view and passes its verified `auth.organization.id`.
export async function pipelinePresentation(
	organizationId: string
): Promise<PipelinePresentationLookup> {
	const { data, error } = await getOwnerSupabaseClient()
		.from('organization_settings')
		.select('pipeline_detailed_assessment_stages, pipeline_inactivity_days')
		.eq('organization_id', organizationId)
		.maybeSingle();

	if (error) {
		console.error('Could not read the pipeline presentation setting.', error);
		return { ok: false, presentation: null };
	}

	// No settings row is a real answer: a brand new organization gets the collapsed board, which is the
	// column's own default.
	return {
		ok: true,
		presentation: {
			detailed_assessment_stages: data?.pipeline_detailed_assessment_stages ?? false,
			// The database checks this holds exactly the seven built-in stages.
			inactivity_days:
				(data?.pipeline_inactivity_days as InactivityDays | undefined) ?? DEFAULT_INACTIVITY_DAYS
		}
	};
}
