<script lang="ts">
	import { onMount } from 'svelte';
	import { navigating, page } from '$app/state';
	import { resolve } from '$app/paths';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import { warmPagesWhenIdle } from '$lib/components/layout/warm-pages';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RouteSkeleton from '$lib/components/layout/RouteSkeleton.svelte';
	import AccountGraceBanner from '$lib/components/layout/AccountGraceBanner.svelte';
	import PausedAccountScreen from '$lib/components/layout/PausedAccountScreen.svelte';
	import SupportMessenger from '$lib/components/support/SupportMessenger.svelte';
	import { setSupportAsk } from '$lib/support/ask';
	import { fallbackContractorNavigation } from '$lib/account/navigation';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();

	// Ask Uplift (D6): a setup section opens the messenger on a new message with that section attached.
	let messenger = $state<ReturnType<typeof SupportMessenger> | null>(null);
	setSupportAsk((context) => messenger?.ask(context));

	// A paused organization sees only the paused screen, so nothing below asks the server anything: every
	// answer would be a refusal, and the menu it feeds is not on screen.
	const standing = $derived(data.standing);
	const paused = $derived(standing?.state === 'paused');

	// The menu comes from the package and the member's permissions, resolved once by the layout load, so
	// it is complete on the first paint: nothing flashes in, and nothing leads only to a refusal screen.
	const navigation = $derived(data.navigation ?? fallbackContractorNavigation);

	// The pages the office moves between all day — the sidebar's daily pages and their record pages — are
	// fetched once the browser is idle (`warmPagesWhenIdle`); everything else loads on hover. The id in the
	// detail paths is a placeholder — only the page's code is fetched, never its data. It must still satisfy the `uuid` route matcher, or `resolve()` yields a path the router can't match
	// and `preloadCode` throws; a nil uuid matches the shape without ever pointing at a real record.
	const WARM_UUID = '00000000-0000-0000-0000-000000000000';
	// Built with individual push() calls, not an array literal: checking that many resolve() calls'
	// own route-id types together as one array expression is what tips TypeScript over its complexity
	// limit (svelte-check: "Expression produces a union type that is too complex to represent"). Each
	// push() argument is checked on its own against the array's plain `string` element type instead.
	const warmRoutes: string[] = [];
	warmRoutes.push(resolve('/(app)/dashboard'));
	warmRoutes.push(resolve('/(app)/schedule'));
	warmRoutes.push(resolve('/(app)/communications'));
	warmRoutes.push(resolve('/(app)/clients'));
	warmRoutes.push(resolve('/(app)/clients/[id=uuid]', { id: WARM_UUID }));
	warmRoutes.push(resolve('/(app)/requests'));
	warmRoutes.push(resolve('/(app)/requests/[id=uuid]', { id: WARM_UUID }));
	warmRoutes.push(resolve('/(app)/quotes'));
	warmRoutes.push(resolve('/(app)/quotes/[id=uuid]', { id: WARM_UUID }));
	warmRoutes.push(resolve('/(app)/jobs'));
	warmRoutes.push(resolve('/(app)/jobs/[id=uuid]', { id: WARM_UUID }));
	warmRoutes.push(resolve('/(app)/invoices'));
	warmRoutes.push(resolve('/(app)/invoices/[id=uuid]', { id: WARM_UUID }));

	// SvelteKit keeps the old page on screen until the next page's code has arrived, so a click on a page
	// whose code isn't here yet looks like nothing happened. Once a move to another page has taken longer
	// than 100 ms — the point where a response stops feeling instant — the content area switches to a
	// skeleton until the page arrives. A page that is already here swaps in first, so it never flashes.
	// Only a change of page counts: a filter or search written into the address stays on the same page.
	// The old page stays mounted but hidden, so a cancelled or failed move brings it back as it was.
	let slowNavigation = $state(false);
	const navigatingToAnotherPage = $derived(
		navigating.to !== null && navigating.to.url.pathname !== page.url.pathname
	);

	$effect(() => {
		if (!navigatingToAnotherPage) {
			slowNavigation = false;
			return;
		}
		const handle = setTimeout(() => (slowNavigation = true), 100);
		return () => clearTimeout(handle);
	});

	onMount(() => {
		if (paused) return;
		return warmPagesWhenIdle(warmRoutes);
	});
</script>

{#if standing?.state === 'paused'}
	<PausedAccountScreen {standing} />
	{#if data.supportOpen}
		<SupportMessenger userId={data.user.id} />
	{/if}
{:else}
	<AppShell
		organizationName={data.organization?.name}
		logoUrl={data.logoUrl}
		account={data.account}
		userId={data.user.id}
		{navigation}
	>
		{#snippet notice()}
			{#if standing?.state === 'grace'}
				<AccountGraceBanner lastAccessDay={standing.last_access_day} />
			{/if}
		{/snippet}
		{#if slowNavigation}
			<PageContainer variant="fill"><RouteSkeleton /></PageContainer>
		{/if}
		<div class="route-content" hidden={slowNavigation}>{@render children()}</div>
		<!-- Inside the shell so it lines up with the content column. Only for someone with an organization:
		     without one there is no team to write on behalf of. -->
		{#if data.organization}
			<SupportMessenger bind:this={messenger} userId={data.user.id} />
		{/if}
	</AppShell>
{/if}

<style lang="scss">
	/* The wrapper exists only to hide the old page during a slow move; it must not change the layout. */
	.route-content {
		display: contents;

		&[hidden] {
			display: none;
		}
	}
</style>
