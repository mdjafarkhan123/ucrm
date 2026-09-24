import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { EffectiveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';

// Who may caption and label a photo (behavior contract, Part 7B). A files.manage holder may describe any
// photo. Anyone else may describe a photo on a job or visit they can add photos to -- the crew member who took
// it knows what it shows -- which is the same field_records.record / manage_team pair that lets them attach
// it. The link read runs under the caller's own policies, so "a job they can see" is the database's answer
// (a field member sees only jobs they are assigned to), not a second copy of that rule here.
export async function canDescribeFile(
	supabase: SupabaseClient<Database>,
	access: EffectiveOrganizationAccess,
	fileId: string
): Promise<boolean> {
	if (hasPermission(access, 'files.manage')) return true;
	if (
		!hasPermission(access, 'field_records.record') &&
		!hasPermission(access, 'field_records.manage_team')
	)
		return false;

	const { data, error } = await supabase
		.from('file_links')
		.select('file_id')
		.eq('file_id', fileId)
		.in('entity_type', ['job', 'visit'])
		.limit(1);
	if (error) throw error;
	return (data ?? []).length > 0;
}
