import type { SupabaseClient } from '@supabase/supabase-js';
import { notFound, validationError } from '$lib/server/api/errors';
import { settingsWriteError } from '$lib/server/settings/errors';

export type LostReasonRow = {
	key: string;
	label: string;
	is_built_in: boolean;
	retired_at: string | null;
};

// The organization's whole list, retired reasons included: a Lost record may carry one, and it must still
// read by name. "Other" always comes last, the rest in the order they were added.
export async function loadLostReasons(
	// Untyped so the accounting export, which holds a plain client, can share it.
	supabase: SupabaseClient,
	organizationId: string
): Promise<{ ok: true; reasons: LostReasonRow[] } | { ok: false }> {
	const { data, error } = await supabase
		.from('pipeline_lost_reasons')
		.select('key, label, is_built_in, retired_at, position')
		.eq('organization_id', organizationId)
		.order('position', { ascending: true });
	if (error) return { ok: false };
	const rows = ((data ?? []) as (LostReasonRow & { position: number })[]).map(
		({ key, label, is_built_in, retired_at }) => ({
			key,
			label,
			is_built_in,
			retired_at
		})
	);
	return {
		ok: true,
		reasons: [
			...rows.filter((row) => row.key !== 'other'),
			...rows.filter((row) => row.key === 'other')
		]
	};
}

// A Lost record stores the reason's key; a person reads its name. An unknown key is shown as it is
// rather than dropped, so nothing is ever silently blank.
export function lostReasonLabeller(reasons: LostReasonRow[]) {
	const labels = new Map(reasons.map((reason) => [reason.key, reason.label]));
	return (key: string | null) => (key === null ? null : (labels.get(key) ?? key));
}

// The two list commands refuse with a sentence the owner should read: a duplicate name (unique_violation)
// and a reason that is not there (no_data_found), on top of the usual settings refusals.
export function lostReasonWriteError(error: { code?: string; message?: string }) {
	if (error.code === '23505')
		return validationError({ label: error.message ?? 'That reason is already on the list.' });
	if (error.code === 'P0002') return notFound(error.message ?? 'That reason could not be found.');
	return settingsWriteError(error);
}
