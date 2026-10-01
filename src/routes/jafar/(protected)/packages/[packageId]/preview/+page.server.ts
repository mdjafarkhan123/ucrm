import { error } from '@sveltejs/kit';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadPackagePreview } from '$lib/server/packages/public-packages';
import type { PageServerLoad } from './$types';

// Package builder: Jafar's "Preview as customer". Only the signed-in platform owner reaches it (the
// protected layout checks that first). It shows the saved draft — or the published edition when there is
// no draft — through the same components visitors see.
export const load: PageServerLoad = async ({ params, url }) => {
	if (!/^[0-9a-f-]{36}$/i.test(params.packageId)) error(404, 'Package not found');
	const preview = await loadPackagePreview(getOwnerSupabaseClient(), params.packageId);
	if (!preview) error(404, 'Package not found');
	return {
		...preview,
		billing: url.searchParams.get('billing') === 'year' ? ('year' as const) : ('month' as const)
	};
};
