<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { loadSurface } from '$lib/design-loading-proof/loaders';
	import { warmPagesWhenIdle } from '$lib/components/layout/warm-pages';
	import type { PageProps } from './$types';
	let { data }: PageProps = $props();
	let Surface = $state<Awaited<ReturnType<typeof loadSurface>> | null>(null);
	let failure = $state(false);
	onMount(() => {
		let active = true;
		void loadSurface(data.design)
			.then((component) => {
				if (active) Surface = component;
			})
			.catch(() => {
				if (active) failure = true;
			});
		const cancel = warmPagesWhenIdle([`/demo/design-loading/${data.design}/details`]);
		return () => {
			active = false;
			cancel?.();
		};
	});
</script>

<svelte:head
	><title>Selected design loading proof</title><meta name="robots" content="noindex" /></svelte:head
>

<data.Shell>
	<div class="proof-content">
		{#if Surface}<Surface surface={data.surface} />
		{:else if failure}<p role="alert">Could not load the proof surface. Reload to retry.</p>
		{:else}<p role="status">Loading proof surface…</p>{/if}
	</div>
	<a
		href={resolve('/demo/design-loading/[design]/[surface]', {
			design: data.design,
			surface: 'details'
		})}
		data-sveltekit-preload-data="hover">Open details</a
	>
</data.Shell>

<style lang="scss">
	.proof-content {
		min-height: 280px;
	}
</style>
