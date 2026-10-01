import type { SupabaseClient } from '@supabase/supabase-js';
import type { CustomStage } from '$lib/pipeline/stages';

// This organization's enabled custom stages, in their saved order. Asked with the member's own client:
// the table's read policy admits anyone who may see the board or the business settings, which are the only
// two places that draw these. At most 25 rows, found through the index that also keeps their names unique.
export async function enabledCustomStages(
	supabase: SupabaseClient,
	organizationId: string
): Promise<{ ok: true; stages: CustomStage[] } | { ok: false; stages: null }> {
	const { data, error } = await supabase
		.from('pipeline_custom_stages')
		.select('id, section, name, after_stage, requires_future_task')
		.eq('organization_id', organizationId)
		.is('disabled_at', null)
		.order('position')
		.order('id');

	if (error) {
		console.error('Could not read the pipeline custom stages.', error);
		return { ok: false, stages: null };
	}
	return { ok: true, stages: (data ?? []) as CustomStage[] };
}
