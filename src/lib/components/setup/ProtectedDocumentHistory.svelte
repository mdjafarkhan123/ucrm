<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Popover from '$lib/components/ui/Popover.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { fetchProtectedDocumentHistory, type ProtectedDocumentEvent } from '$lib/setup/api';

	// Client onboarding B9b: who uploaded, opened and removed one protected document, and when (Jafar's decision
	// 5, 2026-10-04) — "has anyone opened my bill?" always has an answer. The business owner sees it on the setup
	// page, Jafar on the client's page; each passes its own route. Loads when the button is hovered, not with the page.
	let {
		url,
		queryKey,
		name
	}: {
		/** The history route for whoever is looking. */
		url: string;
		queryKey: readonly unknown[];
		name: string;
	} = $props();

	const queryClient = useQueryClient();
	let anchor = $state<HTMLElement | null>(null);
	let open = $state(false);
	let armed = $state(false);

	const history = createQuery(() => ({
		queryKey: [...queryKey],
		queryFn: () => fetchProtectedDocumentHistory(url),
		enabled: armed,
		staleTime: 30_000
	}));

	function warm() {
		armed = true;
		void queryClient.prefetchQuery({
			queryKey: [...queryKey],
			queryFn: () => fetchProtectedDocumentHistory(url),
			staleTime: 30_000
		});
	}

	function show() {
		armed = true;
		open = true;
	}

	const ACTIONS: Record<ProtectedDocumentEvent['action'], string> = {
		uploaded: 'Uploaded',
		refused: 'Refused by the virus check',
		opened: 'Opened',
		removed: 'Removed',
		deletion_scheduled: 'Set to be deleted in 90 days',
		deleted_by_uplift: 'Deleted',
		expired: 'Deleted after 90 days'
	};

	const when = (at: string) =>
		new Date(at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
</script>

<span class="protected-history" bind:this={anchor}>
	<Button variant="tertiary" size="small" onhover={warm} onclick={show}>History</Button>
</span>

{#if open}
	<Popover {open} {anchor} title={`History of ${name}`} onClose={() => (open = false)}>
		{#if history.isPending}
			<LoadingSkeleton variant="text" label="Loading history" />
		{:else if history.isError}
			<ErrorState description={history.error.message} retry={() => history.refetch()} />
		{:else}
			<ol class="protected-history__list">
				{#each history.data as event, index (index)}
					<li class="protected-history__event">
						<span class="protected-history__action">
							{ACTIONS[event.action]}{event.who === 'Automatic' ? '' : ` by ${event.who}`}
						</span>
						<time class="protected-history__when" datetime={event.at}>{when(event.at)}</time>
					</li>
				{/each}
			</ol>
		{/if}
	</Popover>
{/if}

<style lang="scss">
	.protected-history {
		display: inline-flex;

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			min-width: 240px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__event {
			display: flex;
			flex-direction: column;
			gap: 2px;
		}

		&__action {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__when {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
