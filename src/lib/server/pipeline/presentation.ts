import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';

// Whether this organization shows the collapsed five-column board or the seven-column detailed one. It is
// a presentation preference and nothing else: no stage, transition, history or report reads it.
//
// Read fresh every time, never cached the way `organizationFormatting` caches the timezone. Turning the
// toggle on has to show up on the board straight away, and an in-process cache would leave whoever saved
// it — or a teammate on another server — looking at the old board for minutes with nothing visibly wrong.
// This is one primary-key row, asked alongside the counts rather than before them, so it costs the board
// nothing.
export type PipelinePresentation = { detailed_assessment_stages: boolean };

export type PipelinePresentationLookup =
	{ ok: true; presentation: PipelinePresentation } | { ok: false; presentation: null };

export async function pipelinePresentation(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<PipelinePresentationLookup> {
	const { data, error } = await supabase
		.from('organization_settings')
		.select('pipeline_detailed_assessment_stages')
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
			detailed_assessment_stages: data?.pipeline_detailed_assessment_stages ?? false
		}
	};
}
