import { env as publicEnv } from '$env/dynamic/public';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { loadPublicPackages, readLinkChoice } from '$lib/server/packages/public-packages';
import { APPLICATION_EXPERIENCE } from '$lib/experience/definitions';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ url }) => {
	const client = getOwnerSupabaseClient();
	const [packages, settings] = await Promise.all([
		loadPublicPackages(client, APPLICATION_EXPERIENCE),
		getOrCreateOwnerSettings(client)
	]);

	return {
		packages,
		// A marketing-site link may carry ?package=<slug>&billing=month|year to preselect a package.
		linkChoice: readLinkChoice(url, packages),
		privacyPolicyUrl: settings.privacy_policy_url,
		privacyPolicyVersion: settings.privacy_policy_version,
		turnstileSiteKey: publicEnv.PUBLIC_TURNSTILE_SITE_KEY ?? ''
	};
};
