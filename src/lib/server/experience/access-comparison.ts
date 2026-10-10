import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { isKnownExperience } from '$lib/experience/definitions';
import type { AccessComparisonResponse } from '$lib/experience/types';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import {
	compareAccess,
	experienceAwareAccess,
	hasDifferences,
	type ExperienceBasis
} from '$lib/server/access/experience-comparison';
import { loadOrganizationExperienceProfile } from './profile';

type Client = SupabaseClient<Database>;

/**
 * Multi-industry foundation B5: for one Organization, the access it has today beside the access it would
 * have once its Industry experience takes part, for its real Package and each real member. Read-only: it
 * resolves access exactly as the workspace does and changes nothing.
 */

type Basis = {
	basis: AccessComparisonResponse['basis'];
	resolved: ExperienceBasis | null;
};

const unavailable = (explanation: string): Basis => ({
	basis: {
		state: 'unavailable',
		experience: null,
		experience_name: null,
		definition_version: null,
		explanation
	},
	resolved: null
});

async function loadDefinition(client: Client, experienceKey: string, version: number | null) {
	let query = client
		.from('industry_experience_definitions')
		.select('experience_key, version, name, status, capability_families')
		.eq('experience_key', experienceKey);
	query =
		version === null
			? query.eq('status', 'published').order('version', { ascending: false }).limit(1)
			: query.eq('version', version);
	const { data, error } = await query.maybeSingle();
	if (error) throw error;
	return data;
}

async function resolveBasis(
	client: Client,
	organizationId: string,
	editionId: string | null
): Promise<Basis> {
	const profile = await loadOrganizationExperienceProfile(client, organizationId);
	if (profile.state === 'unresolved')
		return unavailable(
			'The decision history could not be read as one chain, so there is nothing safe to compare against.'
		);
	if (profile.state === 'unrecognized')
		return unavailable(
			'The confirmed experience is not available in this version of Uplift, so there is nothing safe to compare against.'
		);

	if (profile.state === 'confirmed') {
		const definition = await loadDefinition(
			client,
			profile.experience,
			profile.decision.definition_version
		);
		if (!definition) return unavailable('The confirmed experience definition could not be found.');
		return {
			basis: {
				state: 'confirmed',
				experience: definition.experience_key,
				experience_name: definition.name,
				definition_version: definition.version,
				explanation: `Compared with the confirmed ${definition.name} experience (definition v${definition.version}).`
			},
			resolved: {
				kind: 'confirmed',
				experience: definition.experience_key,
				definition_version: definition.version,
				families: definition.capability_families
			}
		};
	}

	// No profile yet: judge against the one experience the agreed edition is sold to, never a guess.
	if (!editionId)
		return unavailable(
			'No experience is confirmed and the business has no package, so there is nothing to compare against.'
		);
	const { data: edition, error } = await client
		.from('package_editions')
		.select('experience_keys')
		.eq('id', editionId)
		.maybeSingle();
	if (error) throw error;
	const keys = edition?.experience_keys ?? [];
	if (keys.length !== 1)
		return unavailable(
			'No experience is confirmed and the agreed package is not sold to exactly one experience, so there is nothing to compare against.'
		);
	const definition = await loadDefinition(client, keys[0], null);
	if (!definition || !isKnownExperience(definition.experience_key, definition.version))
		return unavailable(
			'No experience is confirmed and the one the agreed package is sold to is not available in this version of Uplift.'
		);
	return {
		basis: {
			state: 'planned',
			experience: definition.experience_key,
			experience_name: definition.name,
			definition_version: definition.version,
			explanation: `No experience is confirmed yet, so this is compared with ${definition.name}, the experience its package is sold to.`
		},
		resolved: {
			kind: 'planned',
			experience: definition.experience_key,
			definition_version: definition.version,
			families: definition.capability_families
		}
	};
}

const countTrue = (flags: Record<string, boolean>) =>
	Object.values(flags).filter((value) => value === true).length;

export async function loadAccessComparison(
	client: Client,
	organizationId: string
): Promise<AccessComparisonResponse> {
	const organizationAccess = await resolveOrganizationAccess(client, organizationId);
	const { basis, resolved } = await resolveBasis(
		client,
		organizationId,
		organizationAccess.package?.edition_id ?? null
	);
	const packageName = organizationAccess.package?.name ?? null;

	if (!resolved) {
		return {
			basis,
			package_name: packageName,
			capabilities_today: countTrue(organizationAccess.features),
			capabilities_with_experience: 0,
			organization: { features: [] },
			members: [],
			verdict: 'unavailable'
		};
	}

	const [families, membersResult] = await Promise.all([
		client.from('package_capabilities').select('capability_key, capability_family'),
		client
			.from('organization_members')
			.select('user_id, role, created_at')
			.eq('organization_id', organizationId)
			.order('created_at', { ascending: true })
	]);
	if (families.error) throw families.error;
	if (membersResult.error) throw membersResult.error;
	const capabilityFamilies = new Map(
		families.data.map((row) => [row.capability_key, row.capability_family])
	);

	const userIds = membersResult.data.map((member) => member.user_id);
	const profiles = userIds.length
		? await client.from('profiles').select('id, full_name').in('id', userIds)
		: { data: [], error: null };
	if (profiles.error) throw profiles.error;
	const nameById = new Map(profiles.data.map((profile) => [profile.id, profile.full_name]));

	const awareOrganization = experienceAwareAccess(organizationAccess, resolved, capabilityFamilies);
	const organizationDifferences = compareAccess(
		organizationAccess,
		awareOrganization,
		resolved,
		capabilityFamilies
	);

	const members = await Promise.all(
		membersResult.data.map(async (member) => {
			const legacy = await resolveOrganizationAccess(client, organizationId, member.user_id);
			const aware = experienceAwareAccess(legacy, resolved, capabilityFamilies);
			let email: string | null = null;
			try {
				const { data } = await client.auth.admin.getUserById(member.user_id);
				email = data.user?.email ?? null;
			} catch (error) {
				console.error(`Could not resolve auth email for team member ${member.user_id}.`, error);
			}
			return {
				user_id: member.user_id,
				name: nameById.get(member.user_id) ?? null,
				email,
				role: member.role,
				permissions_today: countTrue(legacy.permissions),
				permissions_with_experience: countTrue(aware.permissions),
				differences: compareAccess(legacy, aware, resolved, capabilityFamilies)
			};
		})
	);

	const different =
		organizationDifferences.features.length > 0 ||
		members.some((member) => hasDifferences(member.differences));

	return {
		basis,
		package_name: packageName,
		capabilities_today: countTrue(organizationAccess.features),
		capabilities_with_experience: countTrue(awareOrganization.features),
		organization: { features: organizationDifferences.features },
		members,
		verdict: different ? 'different' : 'same'
	};
}
