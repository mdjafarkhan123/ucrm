<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { navigating, page } from '$app/state';
	import { preloadCode } from '$app/navigation';
	import { resolve } from '$app/paths';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RouteSkeleton from '$lib/components/layout/RouteSkeleton.svelte';
	import AccountGraceBanner from '$lib/components/layout/AccountGraceBanner.svelte';
	import PausedAccountScreen from '$lib/components/layout/PausedAccountScreen.svelte';
	import {
		communicationsAccessKey,
		fetchCommunicationsAccess,
		type CommunicationsAccess
	} from '$lib/communications/inbox';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();

	// A paused organization sees only the paused screen, so nothing below asks the server anything: every
	// answer would be a refusal, and the menu it feeds is not on screen.
	const standing = $derived(data.standing);
	const paused = $derived(standing?.state === 'paused');

	// The Pipeline nav item is the one link in this shell that isn't available to every organization member
	// -- Sales Pipeline is a package entitlement plus its own permission, both already enforced by the route
	// itself. This asks the same question the route asks (so there is one answer, not two), off the
	// blocking SSR path, so a member whose plan or role lacks it never sees a menu item that only leads to a
	// refusal screen.
	//
	// The query key carries the user id: the query client lives in the true root layout and survives
	// sign-out (nothing here clears it), so a key with no identity in it would let a second person who signs
	// in on the same tab within the 5-minute staleTime see the first person's cached verdict -- including two
	// different members of the same organization, whose role (and so their answer) can still differ.
	const pipelineAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'pipeline-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/pipeline/summary');
			if (response.status === 403) return { ok: false };
			return { ok: true };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	// Pipeline is sold separately, so like Marketing it stays hidden until the server says yes.
	const pipelineVisible = $derived(pipelineAccessQuery.data?.ok ?? false);

	// Same idea for Clients: a Field member holds no customers.view and only reaches the clients on their
	// assigned visits, through the job and visit screens. limit=1 keeps the probe to the smallest page.
	const clientsAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'clients-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/clients?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	const clientsVisible = $derived(clientsAccessQuery.data?.ok ?? true);

	// Same idea for Quotes and Invoices: a Field member holds neither quotes.view nor invoices.view, and
	// office/sales/finance can lack invoices.view entirely depending on how the organization set up roles.
	const quotesAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'quotes-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/quotes?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	const quotesVisible = $derived(quotesAccessQuery.data?.ok ?? true);

	const invoicesAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'invoices-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/invoices?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	const invoicesVisible = $derived(invoicesAccessQuery.data?.ok ?? true);

	// Marketing is not in any package yet, so the common answer is "no". It therefore stays hidden until the
	// server says yes, rather than flashing into the menu and disappearing. The probe goes through the page's own
	// route and permission check, so the menu and the page can never disagree about who may see Marketing.
	const marketingAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'marketing-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/marketing/readiness?access=1');
			return { ok: response.ok };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	const marketingVisible = $derived(marketingAccessQuery.data?.ok ?? false);

	// Reviews follows Marketing: hidden until the server says yes, through the workspace's own permission
	// check (reviews.view). Counts is the smallest read behind that check.
	const reviewsAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'reviews-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/reviews/workspace/counts');
			return { ok: response.ok };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	const reviewsVisible = $derived(reviewsAccessQuery.data?.ok ?? false);

	// Same idea for Files: browsing the library is its own files.view permission. A field member holds none
	// of the three file permissions and reaches a photo through the job they are assigned to, so the menu
	// item would only lead them to a refusal screen. limit=1 keeps the probe to the smallest page.
	const filesAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'files-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/files?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	const filesVisible = $derived(filesAccessQuery.data?.ok ?? true);

	// Same idea for the Inbox: sales, finance and field hold no conversations permission by default.
	const inboxAccessQuery = createQuery<CommunicationsAccess>(() => ({
		queryKey: communicationsAccessKey(data.user?.id ?? null),
		queryFn: fetchCommunicationsAccess,
		staleTime: 5 * 60_000,
		enabled: !paused
	}));
	// The shared inbox is sold separately, so like Marketing it stays hidden until the server says yes.
	const inboxVisible = $derived(
		(inboxAccessQuery.data?.ok ?? false) && (inboxAccessQuery.data?.inbox ?? false)
	);

	// Every page is its own JavaScript file, so the first visit to one waits for that file to arrive and
	// the click feels stuck. Once the browser is idle this fetches the code for the pages the office moves
	// between all day — the sidebar's daily pages and their record pages — so those clicks paint straight
	// away. Everything else loads on hover, like any link. Skipped on data saver or 2G (Google quicklink's
	// rule), so a crew member on site doesn't spend mobile data on pages they may never open.
	// The id in the detail paths is a placeholder — only the page's code is fetched, never its data.
	// It must still satisfy the `uuid` route matcher, or `resolve()` yields a path the router can't match
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

	function onConstrainedConnection() {
		const connection = (
			navigator as Navigator & { connection?: { saveData?: boolean; effectiveType?: string } }
		).connection;
		return Boolean(connection?.saveData || connection?.effectiveType?.includes('2g'));
	}

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
		if (paused || onConstrainedConnection()) return;

		const warm = () => {
			for (const path of warmRoutes) void preloadCode(path);
		};

		if ('requestIdleCallback' in window) {
			const handle = requestIdleCallback(warm, { timeout: 3000 });
			return () => cancelIdleCallback(handle);
		}

		const handle = setTimeout(warm, 1000);
		return () => clearTimeout(handle);
	});
</script>

{#if standing?.state === 'paused'}
	<PausedAccountScreen {standing} />
{:else}
	<AppShell
		organizationName={data.organization?.name}
		logoUrl={data.logoUrl}
		account={data.account}
		userId={data.user.id}
		{inboxVisible}
		{pipelineVisible}
		{clientsVisible}
		{quotesVisible}
		{invoicesVisible}
		{marketingVisible}
		{reviewsVisible}
		{filesVisible}
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
