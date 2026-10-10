import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { isKnownExperience } from '$lib/experience/definitions';
import type { ConfirmableExperienceDefinition } from '$lib/experience/types';

/**
 * The Industry experiences Uplift sells to today (multi-industry foundation B3): the newest published
 * definition of each one this build of the app knows how to run, with its Business types in their listed
 * order. The Application offers these to buyers and Uplift confirms one of them during review.
 */
export async function loadOfferedExperiences(
	client: SupabaseClient<Database>
): Promise<ConfirmableExperienceDefinition[]> {
	const [definitions, businessTypes] = await Promise.all([
		client
			.from('industry_experience_definitions')
			.select('experience_key, version, name, capability_families')
			.eq('status', 'published')
			.order('version', { ascending: false }),
		client
			.from('industry_experience_business_types')
			.select('experience_key, definition_version, business_type_key, label')
			.order('position')
	]);
	if (definitions.error) throw definitions.error;
	if (businessTypes.error) throw businessTypes.error;

	const newest = new Map<string, (typeof definitions.data)[number]>();
	for (const definition of definitions.data ?? [])
		if (!newest.has(definition.experience_key)) newest.set(definition.experience_key, definition);

	return [...newest.values()]
		.filter((definition) => isKnownExperience(definition.experience_key, definition.version))
		.map((definition) => ({
			experience_key: definition.experience_key,
			version: definition.version,
			name: definition.name,
			capability_families: definition.capability_families,
			business_types: (businessTypes.data ?? [])
				.filter(
					(type) =>
						type.experience_key === definition.experience_key &&
						type.definition_version === definition.version
				)
				.map((type) => ({ key: type.business_type_key, label: type.label }))
		}));
}
