import { env as publicEnv } from '$env/dynamic/public';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { loadPublicPackages, readLinkChoice } from '$lib/server/packages/public-packages';
import { loadOfferedExperiences } from '$lib/server/experience/offered';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ url }) => {
	const client = getOwnerSupabaseClient();
	const [experiences, settings] = await Promise.all([
		loadOfferedExperiences(client),
		getOrCreateOwnerSettings(client)
	]);
	// Multi-industry foundation B3: each kind of business is shown only the packages sold to it.
	const packagesByExperience = Object.fromEntries(
		await Promise.all(
			experiences.map(
				async (experience) =>
					[
						experience.experience_key,
						await loadPublicPackages(client, experience.experience_key)
					] as const
			)
		)
	);
	const allPackages = [
		...new Map(
			Object.values(packagesByExperience)
				.flat()
				.map((pkg) => [pkg.edition_id, pkg])
		).values()
	];

	// A marketing-site link may carry ?type=<business type> to suggest the kind of business; the applicant
	// can still change it.
	const askedType = url.searchParams.get('type')?.trim().toLowerCase() ?? '';
	const linkedExperience = experiences.find((experience) =>
		experience.business_types.some((type) => type.key === askedType)
	);

	return {
		experiences: experiences.map((experience) => ({
			key: experience.experience_key,
			name: experience.name,
			business_types: experience.business_types
		})),
		packagesByExperience,
		linkBusinessType: linkedExperience
			? { experience_key: linkedExperience.experience_key, business_type_key: askedType }
			: null,
		// A marketing-site link may carry ?package=<slug>&billing=month|year to preselect a package.
		linkChoice: readLinkChoice(url, allPackages),
		privacyPolicyUrl: settings.privacy_policy_url,
		privacyPolicyVersion: settings.privacy_policy_version,
		turnstileSiteKey: publicEnv.PUBLIC_TURNSTILE_SITE_KEY ?? ''
	};
};
