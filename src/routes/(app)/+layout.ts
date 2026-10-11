import type { LayoutLoad } from './$types';

// Resolve the frame before SSR and hydration. Explicit imports preserve separate delivery graphs.
export const load: LayoutLoad = async ({ data }) => ({
	...data,
	ShellFrame:
		data.presentation === 'botanical'
			? (await import('$lib/components/layout/presentations/BotanicalFrame.svelte')).default
			: (await import('$lib/components/layout/presentations/ClassicFrame.svelte')).default
});
