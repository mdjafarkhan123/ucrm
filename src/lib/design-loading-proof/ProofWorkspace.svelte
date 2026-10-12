<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { loadOverlay, loadSurface } from '$lib/design-loading-proof/loaders';
	import { warmPagesWhenIdle } from '$lib/components/layout/warm-pages';
	import type { ProofDesign } from './loaders';
	import type { Component, Snippet } from 'svelte';
	let {
		design,
		surface,
		Shell
	}: {
		design: ProofDesign;
		surface: string;
		Shell: Component<{ children: Snippet }>;
	} = $props();
	let Surface = $state<Awaited<ReturnType<typeof loadSurface>> | null>(null);
	let failure = $state(false);
	let Overlay = $state<Awaited<ReturnType<typeof loadOverlay>> | null>(null);
	let overlayOpen = $state(false);
	let overlayFailure = $state(false);
	let overlayRequest: ReturnType<typeof loadOverlay> | null = null;

	// The selected overlay loads on intent; the other presentation never joins the warm list.
	async function prepareOverlay() {
		// Browsers retain failed dynamic-import URLs. A fresh visit is the reliable retry.
		if (overlayFailure) return;
		try {
			overlayRequest ??= loadOverlay(design);
			Overlay = await overlayRequest;
		} catch {
			overlayRequest = null;
			overlayFailure = true;
		}
	}

	async function openOverlay() {
		await prepareOverlay();
		if (Overlay) overlayOpen = true;
	}

	onMount(() => {
		let active = true;
		void loadSurface(design)
			.then((component) => {
				if (active) Surface = component;
			})
			.catch(() => {
				if (active) failure = true;
			});
		const cancel = warmPagesWhenIdle([`/demo/design-loading/${design}/details`]);
		return () => {
			active = false;
			cancel?.();
		};
	});
</script>

<Shell>
	<div class="proof-content">
		{#if Surface}<Surface {surface} />
		{:else if failure}<p role="alert">Could not load the proof surface. Reload to retry.</p>
		{:else}<p role="status">Loading proof surface…</p>{/if}
	</div>
	<a
		href={resolve('/demo/design-loading/[design]/[surface]', {
			design: design,
			surface: 'details'
		})}
		data-sveltekit-preload-data="hover">Open details</a
	>
	<div class="proof-content__actions">
		<button
			type="button"
			disabled={overlayFailure}
			onmouseenter={() => void prepareOverlay()}
			onfocus={() => void prepareOverlay()}
			onclick={() => void openOverlay()}>Open read-only example</button
		>
		<a
			href={resolve('/demo/design-loading/[design]/[surface]', {
				design: design === 'classic' ? 'botanical' : 'classic',
				surface: 'overview'
			})}
			data-sveltekit-preload-data="off"
			data-sveltekit-preload-code="off">Load other test presentation</a
		>
	</div>
	{#if overlayFailure}
		<p role="alert">
			Could not load the example.
			<a
				href={resolve('/demo/design-loading/[design]/[surface]', { design, surface })}
				data-sveltekit-reload>Reload to retry</a
			>
		</p>
	{/if}
</Shell>

{#if Overlay}<Overlay open={overlayOpen} onClose={() => (overlayOpen = false)} />{/if}

<style lang="scss">
	.proof-content__actions {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 16px;
	}

	.proof-content {
		min-height: 280px;
	}
</style>
