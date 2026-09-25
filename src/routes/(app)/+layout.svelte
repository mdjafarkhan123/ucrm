<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { preloadCode } from '$app/navigation';
	import { resolve } from '$app/paths';
	import AppShell from '$lib/components/layout/AppShell.svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();

	// The Pipeline nav item is the one link in this shell that isn't available to every organization member
	// -- Sales Pipeline is a package entitlement plus its own permission, both already enforced by the route
	// itself. This asks the same question the route asks (so there is one answer, not two), off the
	// blocking SSR path, so a Starter-tier or unpermitted member never sees a menu item that only leads to a
	// refusal screen. Defaults to visible until the answer is back, since hiding is the exception, not the
	// common case.
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
		staleTime: 5 * 60_000
	}));
	const pipelineVisible = $derived(pipelineAccessQuery.data?.ok ?? true);

	// Same idea for Clients: a Field member holds no customers.view and only reaches the clients on their
	// assigned visits, through the job and visit screens. limit=1 keeps the probe to the smallest page.
	const clientsAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'clients-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/clients?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000
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
		staleTime: 5 * 60_000
	}));
	const quotesVisible = $derived(quotesAccessQuery.data?.ok ?? true);

	const invoicesAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'invoices-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/invoices?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000
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
		staleTime: 5 * 60_000
	}));
	const marketingVisible = $derived(marketingAccessQuery.data?.ok ?? false);

	// Same idea for Files: browsing the library is its own files.view permission. A field member holds none
	// of the three file permissions and reaches a photo through the job they are assigned to, so the menu
	// item would only lead them to a refusal screen. limit=1 keeps the probe to the smallest page.
	const filesAccessQuery = createQuery<{ ok: boolean }>(() => ({
		queryKey: ['nav', 'files-access', data.user?.id ?? null],
		queryFn: async () => {
			const response = await fetch('/api/files?limit=1');
			return { ok: response.status !== 403 };
		},
		staleTime: 5 * 60_000
	}));
	const filesVisible = $derived(filesAccessQuery.data?.ok ?? true);

	// Every page is its own JavaScript file, so the first visit to one waits for that file to arrive and
	// the click feels stuck. This fetches the files for the pages the office moves between all day once
	// the browser has nothing else to do, so those clicks paint straight away. Hovering a link already
	// does the same thing on its own; this covers the clicks that come too fast for a hover.
	// The id in the detail paths is a placeholder — only the page's code is fetched, never its data.
	// It must still satisfy the `uuid` route matcher, or `resolve()` yields a path the router can't match
	// and `preloadCode` throws; a nil uuid matches the shape without ever pointing at a real record.
	const WARM_UUID = '00000000-0000-0000-0000-000000000000';
	const warmRoutes = [
		resolve('/(app)/dashboard'),
		resolve('/(app)/schedule'),
		resolve('/(app)/clients'),
		resolve('/(app)/clients/new'),
		resolve('/(app)/clients/[id=uuid]', { id: WARM_UUID }),
		resolve('/(app)/requests'),
		resolve('/(app)/requests/new'),
		resolve('/(app)/requests/[id=uuid]', { id: WARM_UUID }),
		resolve('/(app)/quotes'),
		resolve('/(app)/quotes/new'),
		resolve('/(app)/jobs'),
		resolve('/(app)/jobs/new'),
		resolve('/(app)/jobs/[id=uuid]', { id: WARM_UUID }),
		resolve('/(app)/invoices'),
		resolve('/(app)/invoices/new'),
		resolve('/(app)/invoices/ready-to-bill'),
		resolve('/(app)/invoices/send'),
		resolve('/(app)/invoices/[id=uuid]', { id: WARM_UUID }),
		resolve('/(app)/pipeline'),
		resolve('/(app)/pipeline/outcomes'),
		resolve('/(app)/marketing'),
		resolve('/(app)/marketing/campaigns/new'),
		resolve('/(app)/marketing/campaigns/[id=uuid]', { id: WARM_UUID }),
		resolve('/(app)/marketing/campaigns/[id=uuid]/edit', { id: WARM_UUID }),
		resolve('/(app)/communications'),
		resolve('/(app)/reviews/settings'),
		resolve('/(app)/files'),
		resolve('/(app)/settings'),
		resolve('/(app)/settings/business-profile'),
		resolve('/(app)/settings/branding'),
		resolve('/(app)/settings/business-hours'),
		resolve('/(app)/settings/taxes'),
		resolve('/(app)/settings/price-book'),
		resolve('/(app)/settings/quotes'),
		resolve('/(app)/settings/invoices'),
		resolve('/(app)/settings/payments'),
		resolve('/(app)/settings/forms'),
		resolve('/(app)/settings/communications/email'),
		resolve('/(app)/settings/communications/sms'),
		resolve('/(app)/settings/communications/sms-usage'),
		resolve('/(app)/settings/communications/blocked-addresses'),
		resolve('/(app)/settings/communications/website-chat'),
		resolve('/(app)/settings/communications/snippets'),
		resolve('/(app)/settings/communications/templates'),
		resolve('/(app)/settings/inquiry-alerts'),
		resolve('/(app)/settings/team'),
		resolve('/(app)/settings/team/[userId]', { userId: 'warm' }),
		resolve('/(app)/settings/team/activity')
	];

	onMount(() => {
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

<AppShell
	organizationName={data.organization?.name}
	logoUrl={data.logoUrl}
	account={data.account}
	userId={data.user.id}
	{pipelineVisible}
	{clientsVisible}
	{quotesVisible}
	{invoicesVisible}
	{marketingVisible}
	{filesVisible}>{@render children()}</AppShell
>
