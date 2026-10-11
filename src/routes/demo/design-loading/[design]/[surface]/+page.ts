import { loadShell } from '$lib/design-loading-proof/loaders';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ data }) => ({
	...data,
	Shell: await loadShell(data.design)
});
