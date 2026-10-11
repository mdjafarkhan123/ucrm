import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

// Explicit opt-in for a locally served release build. No account or organization setting is changed.
export const load: PageServerLoad = ({ params, url }) => {
	if (env.DESIGN_LOADING_PROOF !== '1' || !['localhost', '127.0.0.1'].includes(url.hostname)) {
		error(404, 'Not found');
	}
	if (
		!['classic', 'botanical'].includes(params.design) ||
		!['overview', 'details'].includes(params.surface)
	) {
		error(404, 'Not found');
	}
	return { design: params.design as 'classic' | 'botanical', surface: params.surface };
};
