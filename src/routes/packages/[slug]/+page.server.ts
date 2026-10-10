import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadPublicPackages } from '$lib/server/packages/public-packages';
import { APPLICATION_EXPERIENCE } from '$lib/experience/definitions';
import type { PageServerLoad } from './$types';

// Package builder P9: the public details page a marketing-site "View details" link opens. It always shows
// the package's current published edition; a private, archived, or unknown package gets an explanation.
export const load: PageServerLoad = async ({ params, url }) => {
	const slug = params.slug.trim().toLowerCase();
	const [pkg] = /^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)
		? await loadPublicPackages(getOwnerSupabaseClient(), APPLICATION_EXPERIENCE, slug)
		: [];
	const billing = url.searchParams.get('billing');
	return { pkg: pkg ?? null, billing: billing === 'year' ? ('year' as const) : ('month' as const) };
};
