<script lang="ts">
	import '$lib/styles/app.scss';
	import favicon from '$lib/assets/favicon.svg';
	import { QueryClientProvider } from '@tanstack/svelte-query';
	import { createQueryClient } from '$lib/query-client';
	import ToastViewport from '$lib/components/ui/ToastViewport.svelte';
	import { createToastManager, provideToastManager } from '$lib/components/ui/ToastManager.svelte';

	let { children } = $props();

	const queryClient = createQueryClient();
	const toastManager = createToastManager();
	provideToastManager(toastManager);
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<script>
		(() => {
			const savedTheme = localStorage.getItem('ucrm-theme');
			const theme =
				savedTheme ?? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
			document.documentElement.dataset.theme = theme;
		})();
	</script>
</svelte:head>

<QueryClientProvider client={queryClient}>
	<ToastViewport manager={toastManager} />
	{@render children()}
</QueryClientProvider>
