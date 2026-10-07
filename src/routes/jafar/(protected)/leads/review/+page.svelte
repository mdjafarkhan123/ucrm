<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LeadReviewCard from '$lib/components/jafar/leads/LeadReviewCard.svelte';
	import { countryName } from '$lib/jafar/leads';
	import { leadExclusion, type ReviewQueuePage } from '$lib/jafar/lead-review';
	import { jafarLeadReviewKey } from '$lib/jafar/query-keys';
	import { canUseJafarPath } from '$lib/jafar/team-access';

	// Jafar business management B3: the Leads waiting for Jafar's decision, oldest first, one at a time. Each
	// card shows why the business is proposed and lets him approve chosen contact details or send it back.
	// Approving never sends anything.

	const viewer = $derived({ role: page.data.owner.role, access: page.data.owner.access });
	const canApprove = $derived(canUseJafarPath(viewer, '/api/jafar/leads/x/approval', 'POST'));
	const canMarkUnsuitable = $derived(canUseJafarPath(viewer, '/api/jafar/leads/x', 'PATCH'));

	const toast = getToastManager();

	const queue = createInfiniteQuery<ReviewQueuePage>(() => ({
		queryKey: jafarLeadReviewKey,
		queryFn: async ({ pageParam }) => {
			const query = typeof pageParam === 'string' ? `?cursor=${encodeURIComponent(pageParam)}` : '';
			const response = await fetch(`/api/jafar/leads/review${query}`);
			const result = (await response.json()) as ReviewQueuePage & { error?: string };
			if (!response.ok) throw new Error(result.error ?? 'The review queue could not be loaded.');
			return result;
		},
		initialPageParam: null as string | null,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined
	}));

	const leads = $derived(queue.data?.pages.flatMap((entry) => entry.leads) ?? []);
	const total = $derived(queue.data?.pages[0]?.total ?? 0);

	// The Lead on screen lives in the address, so a refresh or a shared link opens the same one.
	const wantedId = $derived(page.url.searchParams.get('lead'));
	const currentIndex = $derived.by(() => {
		if (leads.length === 0) return -1;
		const index = wantedId ? leads.findIndex((lead) => lead.id === wantedId) : -1;
		return index === -1 ? 0 : index;
	});
	const current = $derived(currentIndex === -1 ? null : leads[currentIndex]);

	function show(id: string | null) {
		const base = resolve('/jafar/leads/review');
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the path comes from resolve(); only the query string is added.
		void goto(id ? `${base}?lead=${encodeURIComponent(id)}` : base, {
			keepFocus: true,
			noScroll: true,
			replaceState: true
		});
	}

	function step(by: number) {
		const next = leads[currentIndex + by];
		if (next) show(next.id);
		else if (by > 0 && queue.hasNextPage) void queue.fetchNextPage();
	}

	// After a decision the Lead leaves the queue: move to the one after it, or the one before at the end.
	function decided(message: string) {
		toast.success(message);
		const next = leads[currentIndex + 1] ?? leads[currentIndex - 1] ?? null;
		show(next?.id ?? null);
	}

	// Keep the next page ready while the last loaded card is on screen.
	$effect(() => {
		if (currentIndex >= leads.length - 2 && queue.hasNextPage && !queue.isFetchingNextPage)
			void queue.fetchNextPage();
	});
</script>

<svelte:head><title>Approve who to contact · Leads · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="review">
	<a class="review__back" href={resolve('/jafar/leads')}
		><span aria-hidden="true">{@html arrowLeftIcon}</span> Leads</a
	>

	<header class="review__header">
		<div>
			<p class="review__eyebrow">Business management</p>
			<h1>Approve who to contact</h1>
			<p class="review__description">
				Leads marked Ready for review, oldest first. Approving a contact detail sends nothing — it
				gives the Lead a first-contact task, and you contact them yourself.
			</p>
		</div>
		{#if current}
			<nav class="review__stepper" aria-label="Move through the queue">
				<button
					type="button"
					class="review__step"
					disabled={currentIndex <= 0}
					onclick={() => step(-1)}
					aria-label="Previous Lead"
				>
					<span class="review__icon" aria-hidden="true">{@html chevronLeftIcon}</span>
				</button>
				<span class="review__position" aria-live="polite"
					><strong>{currentIndex + 1}</strong> of {total}</span
				>
				<button
					type="button"
					class="review__step"
					disabled={currentIndex >= leads.length - 1 && !queue.hasNextPage}
					onclick={() => step(1)}
					aria-label="Next Lead"
				>
					<span class="review__icon" aria-hidden="true">{@html chevronRightIcon}</span>
				</button>
			</nav>
		{/if}
	</header>

	{#if queue.isPending}
		<div class="review__layout">
			<div class="review__main"><LoadingSkeleton variant="card" rows={8} /></div>
			<div class="review__rail"><LoadingSkeleton variant="card" rows={5} /></div>
		</div>
	{:else if queue.isError}
		<ErrorState
			title="The review queue could not be loaded"
			description={queue.error.message}
			retry={() => queue.refetch()}
		/>
	{:else if !current}
		<div class="review__empty">
			<EmptyState
				title="Nothing waiting for review"
				description="When a Lead is researched and marked Ready for review, it appears here for your decision."
			/>
			<div>
				<Button href={resolve('/jafar/leads')} variant="secondary">Back to Leads</Button>
			</div>
		</div>
	{:else}
		<div class="review__layout">
			<div class="review__main">
				{#key current.id}
					<LeadReviewCard lead={current} {canApprove} {canMarkUnsuitable} onDone={decided} />
				{/key}
			</div>

			<aside class="review__rail" aria-label="Waiting for review">
				<h2>Waiting <span>{total}</span></h2>
				<ol class="review__list">
					{#each leads as lead, index (lead.id)}
						{@const excluded = leadExclusion(lead)}
						<li>
							<button
								type="button"
								class={['review__item', index === currentIndex && 'review__item--current']}
								aria-current={index === currentIndex ? 'true' : undefined}
								onclick={() => show(lead.id)}
							>
								<span class="review__item-name">{lead.business_name}</span>
								<span class="review__item-meta">
									{lead.trade} · {countryName(lead.country_code)}
								</span>
								{#if excluded}
									<span class="review__item-excluded"
										><span aria-hidden="true">{@html banIcon}</span>Excluded</span
									>
								{/if}
							</button>
						</li>
					{/each}
				</ol>
				{#if queue.hasNextPage}
					<Button
						variant="tertiary"
						size="small"
						disabled={queue.isFetchingNextPage}
						onclick={() => queue.fetchNextPage()}
						>{queue.isFetchingNextPage ? 'Loading more…' : 'Load more'}</Button
					>
				{/if}
			</aside>
		</div>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.review {
		min-width: 0;
		display: grid;
		gap: var(--space-large);

		h1,
		h2,
		p {
			margin: 0;
		}

		h1 {
			color: var(--color-heading);
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-jumbo);
			font-weight: 900;
			line-height: var(--typography--lineHeight-minuscule);
		}
	}

	.review__back {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		width: fit-content;
		color: var(--color-text--secondary);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			color: var(--color-interactive);
		}

		&:focus-visible {
			border-radius: var(--radius-small);
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		span :global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.review__header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.review__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.review__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.review__stepper {
		display: flex;
		flex: none;
		align-items: center;
		gap: var(--space-small);
	}

	.review__position {
		min-width: 64px;
		color: var(--color-text--secondary);
		text-align: center;
		white-space: nowrap;

		strong {
			color: var(--color-heading);
		}
	}

	.review__step {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 36px;
		height: 36px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		color: var(--color-heading);
		cursor: pointer;
		transition:
			background-color var(--timing-quick),
			border-color var(--timing-quick);

		&:hover:not(:disabled) {
			border-color: var(--color-interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			color: var(--color-text--secondary);
			cursor: not-allowed;
			opacity: 0.5;
		}
	}

	.review__icon {
		display: inline-flex;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.review__layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 280px;
		align-items: start;
		gap: var(--space-large);
	}

	.review__main {
		min-width: 0;
	}

	.review__rail {
		position: sticky;
		top: var(--space-large);
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		h2 {
			display: flex;
			align-items: center;
			justify-content: space-between;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;

			span {
				color: var(--color-text--secondary);
				font-weight: 600;
			}
		}
	}

	.review__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		max-height: 60vh;
		margin: 0;
		padding: 0;
		overflow-y: auto;
		list-style: none;
	}

	.review__item {
		display: flex;
		flex-direction: column;
		gap: 2px;
		width: 100%;
		padding: var(--space-small) var(--space-slim);
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		background: none;
		color: var(--color-text);
		font: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			background-color var(--timing-quick),
			border-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.review__item--current {
		border-color: var(--color-interactive);
		background: var(--color-surface--background--subtle);
	}

	.review__item-name {
		color: var(--color-heading);
		font-weight: 600;
		overflow-wrap: anywhere;
	}

	.review__item-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.review__item-excluded {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		span :global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.review__empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-largest);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	// The queue list is a convenience on a wide screen; on a phone the arrows move through it.
	@media (max-width: 1023px) {
		.review__layout {
			grid-template-columns: minmax(0, 1fr);
		}

		.review__rail {
			display: none;
		}
	}

	@media (max-width: 767px) {
		.review__header {
			flex-direction: column;
			align-items: stretch;
		}

		.review__stepper {
			justify-content: space-between;
		}
	}

	@media (max-width: 639px) {
		.review h1 {
			font-size: 28px;
		}
	}
</style>
