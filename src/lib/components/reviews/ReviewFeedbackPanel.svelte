<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		DEFAULT_REVIEW_FEEDBACK_FILTERS,
		REVIEW_FEEDBACK_STATUSES,
		REVIEW_FEEDBACK_STATUS_LABELS,
		REVIEW_FEEDBACK_STATUS_TONES,
		fetchReviewFeedback,
		formatFeedbackAnswer,
		reviewFeedbackKey,
		setReviewFeedbackStatus,
		type ReviewFeedbackFilter,
		type ReviewFeedbackItem,
		type ReviewFeedbackPage,
		type ReviewFeedbackStatus
	} from '$lib/reviews/feedback';
	import { reviewWorkspaceKey } from '$lib/reviews/workspace';
	import starIcon from '@tabler/icons/filled/star.svg?raw';
	import starOutlineIcon from '@tabler/icons/outline/star.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import playIcon from '@tabler/icons/outline/player-play.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import reopenIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';

	// Google review campaign Part 5B: private-feedback recovery. Each item is one customer who chose to tell the
	// business privately -- shown whole (their answers, how to reach them) with the next step one press away.
	/* eslint-disable svelte/no-navigation-without-resolve -- every href below comes from resolve() or is a tel: link */
	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<ReviewFeedbackFilter>(DEFAULT_REVIEW_FEEDBACK_FILTERS.status);

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ search: debouncedSearch.trim(), status });
	const hasFilters = $derived(filters.search !== '' || filters.status !== 'open');

	const feedbackQuery = createInfiniteQuery(() => ({
		queryKey: reviewFeedbackKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchReviewFeedback(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: ReviewFeedbackPage) => lastPage.next_cursor ?? undefined
	}));
	const items = $derived(feedbackQuery.data?.pages.flatMap((page) => page.feedback) ?? []);
	const refused = $derived((feedbackQuery.error as { status?: number } | null)?.status === 403);

	const statusOptions = [
		{ value: 'open', label: 'Needs attention' },
		{ value: 'all', label: 'Everything' },
		...REVIEW_FEEDBACK_STATUSES.map((value) => ({
			value,
			label: REVIEW_FEEDBACK_STATUS_LABELS[value]
		}))
	];

	const dateTime = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});

	// The one step that usually comes next; every other status stays reachable from the menu.
	const NEXT_STEP: Record<
		ReviewFeedbackStatus,
		{ to: ReviewFeedbackStatus; label: string; icon: string }
	> = {
		new: { to: 'contacting', label: 'Start contacting', icon: playIcon },
		contacting: { to: 'resolved', label: 'Mark resolved', icon: checkIcon },
		resolved: { to: 'closed', label: 'Close', icon: archiveIcon },
		closed: { to: 'new', label: 'Reopen', icon: reopenIcon }
	};
	const TOAST_TEXT: Record<ReviewFeedbackStatus, string> = {
		new: 'Moved back to New',
		contacting: 'Marked as contacting the customer',
		resolved: 'Marked as resolved',
		closed: 'Closed'
	};

	let busyId = $state<string | null>(null);
	async function move(item: ReviewFeedbackItem, next: ReviewFeedbackStatus) {
		if (busyId) return;
		busyId = item.id;
		try {
			await setReviewFeedbackStatus(item.id, next);
			// The request list and the four numbers above it show the same feedback, so they refresh too.
			await queryClient.invalidateQueries({ queryKey: reviewWorkspaceKey });
			toast.success(TOAST_TEXT[next]);
		} catch (error) {
			toast.error((error as Error).message);
		} finally {
			busyId = null;
		}
	}

	function menuItems(item: ReviewFeedbackItem) {
		const menu: { label: string; icon: string; onSelect: () => void }[] = [];
		const clientLink = clientHref(item);
		const jobLink = jobHref(item);
		if (clientLink) {
			menu.push({ label: 'View client', icon: userIcon, onSelect: () => void goto(clientLink) });
		}
		if (jobLink) {
			menu.push({ label: 'View job', icon: briefcaseIcon, onSelect: () => void goto(jobLink) });
		}
		for (const value of REVIEW_FEEDBACK_STATUSES) {
			if (value === item.status || value === NEXT_STEP[item.status].to) continue;
			menu.push({
				label: `Move to ${REVIEW_FEEDBACK_STATUS_LABELS[value]}`,
				icon: NEXT_STEP[value].icon,
				onSelect: () => void move(item, value)
			});
		}
		return menu;
	}

	// Annotated: without it TypeScript gives up on the route-id union ("too complex") at the resolve() call.
	function clientHref(item: ReviewFeedbackItem): string | null {
		if (!item.client) return null;
		return resolve('/(app)/clients/[id=uuid]', { id: item.client.id });
	}
	function jobHref(item: ReviewFeedbackItem): string | null {
		if (!item.job_id) return null;
		return resolve('/(app)/jobs/[id=uuid]', { id: item.job_id });
	}
	function inboxHref(item: ReviewFeedbackItem): string | null {
		if (!item.client) return null;
		return `${resolve('/(app)/communications')}?client=${item.client.id}`;
	}
	function telHref(phone: string) {
		return `tel:${phone.replace(/[^\d+]/g, '')}`;
	}

	function answered(item: ReviewFeedbackItem) {
		return item.questions
			.map((question) => ({
				id: question.id,
				label: question.label,
				answer: formatFeedbackAnswer(item.answers[question.id])
			}))
			.filter((entry) => entry.answer !== null);
	}

	function clearFilters() {
		search = '';
		debouncedSearch = '';
		status = DEFAULT_REVIEW_FEEDBACK_FILTERS.status;
	}
</script>

<section class="feedback" aria-labelledby="reviews-feedback-heading">
	<div class="feedback__head">
		<h2 id="reviews-feedback-heading">Private feedback</h2>
		<p>
			Customers who chose to tell you privately instead of posting a review. Reach out quickly to
			make it right.
		</p>
	</div>

	{#if !refused}
		<div class="feedback__toolbar">
			<div class="feedback__search">
				<SearchInput
					id="reviews-feedback-search"
					bind:value={search}
					placeholder="Search by client name"
				/>
			</div>
			<div class="feedback__select">
				<Select
					id="reviews-feedback-status"
					ariaLabel="Filter by status"
					bind:value={status}
					options={statusOptions}
				/>
			</div>
			{#if hasFilters}
				<Button variant="secondary" onclick={clearFilters}>Clear</Button>
			{/if}
		</div>
	{/if}

	{#if feedbackQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading private feedback" rows={3} />
	{:else if refused}
		<EmptyState
			icon={inboxIcon}
			title="You do not have access to private feedback"
			description="Ask an owner or admin to give you access."
		/>
	{:else if feedbackQuery.isError}
		<ErrorState
			description="Private feedback could not be loaded. Refresh and try again."
			retry={() => feedbackQuery.refetch()}
		/>
	{:else if items.length === 0}
		<EmptyState
			icon={inboxIcon}
			title={hasFilters ? 'No matching feedback' : 'Nothing needs your attention'}
			description={hasFilters
				? 'Try a different search or show everything.'
				: 'When a customer tells you privately how a job went, it will appear here and you will get an alert.'}
		/>
	{:else}
		<ul class="feedback__list">
			{#each items as item (item.id)}
				{@const next = NEXT_STEP[item.status]}
				{@const entries = answered(item)}
				{@const clientLink = clientHref(item)}
				{@const messageLink = inboxHref(item)}
				<li>
					<article class={`feedback-card feedback-card--${item.status}`}>
						<header class="feedback-card__head">
							<Avatar
								id={item.client?.id ?? item.id}
								name={item.client?.name ?? 'Client removed'}
								size="medium"
							/>
							<div class="feedback-card__who">
								{#if clientLink}
									<a class="feedback-card__name" href={clientLink}>{item.client?.name}</a>
								{:else}
									<span class="feedback-card__name feedback-card__name--muted">Client removed</span>
								{/if}
								<span class="feedback-card__sub">
									{#if item.job_number}
										Job #{item.job_number}{item.job_title ? ` · ${item.job_title}` : ''}
									{:else}
										No particular job
									{/if}
									· {dateTime.format(new Date(item.submitted_at))}
								</span>
							</div>
							<div class="feedback-card__state">
								{#if item.rating}
									<span
										class="feedback-card__stars"
										role="img"
										aria-label={`${item.rating} out of 5 stars`}
									>
										{#each [1, 2, 3, 4, 5] as star (star)}
											<span class:feedback-card__star--on={star <= item.rating} aria-hidden="true">
												<!-- eslint-disable-next-line svelte/no-at-html-tags -->
												{@html star <= item.rating ? starIcon : starOutlineIcon}
											</span>
										{/each}
									</span>
								{:else}
									<span class="feedback-card__unrated">No star rating</span>
								{/if}
								<StatusBadge status={REVIEW_FEEDBACK_STATUS_TONES[item.status]}>
									{REVIEW_FEEDBACK_STATUS_LABELS[item.status]}
								</StatusBadge>
							</div>
						</header>

						{#if entries.length > 0}
							<dl class="feedback-card__answers">
								{#each entries as entry (entry.id)}
									<div class="feedback-card__answer">
										<dt>{entry.label}</dt>
										<dd>{entry.answer}</dd>
									</div>
								{/each}
							</dl>
						{:else}
							<p class="feedback-card__none">They sent feedback without writing anything.</p>
						{/if}

						<footer class="feedback-card__actions">
							<div class="feedback-card__contact">
								{#if item.client?.phone}
									<Button variant="secondary" size="small" href={telHref(item.client.phone)}>
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										<span class="feedback-card__icon" aria-hidden="true">{@html phoneIcon}</span>
										Call {item.client.phone}
									</Button>
								{/if}
								{#if messageLink}
									<Button variant="secondary" size="small" href={messageLink}>
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										<span class="feedback-card__icon" aria-hidden="true">{@html messageIcon}</span>
										Message
									</Button>
								{/if}
							</div>
							<div class="feedback-card__steps">
								<Button
									variant={item.status === 'closed' ? 'secondary' : 'primary'}
									size="small"
									loading={busyId === item.id}
									onclick={() => void move(item, next.to)}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									<span class="feedback-card__icon" aria-hidden="true">{@html next.icon}</span>
									{next.label}
								</Button>
								<DropdownMenu
									items={menuItems(item)}
									triggerLabel={`More actions for ${item.client?.name ?? 'this feedback'}`}
								/>
							</div>
						</footer>
					</article>
				</li>
			{/each}
		</ul>
		<ListLoadMore
			hasNextPage={feedbackQuery.hasNextPage}
			isFetchingNextPage={feedbackQuery.isFetchingNextPage}
			onLoadMore={() => feedbackQuery.fetchNextPage()}
		/>
	{/if}
</section>

<style lang="scss">
	.feedback {
		display: grid;
		gap: var(--space-base);
	}

	.feedback__head {
		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
		}

		p {
			margin: var(--space-smaller) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.feedback__toolbar {
		display: flex;
		align-items: stretch;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.feedback__search {
		flex: 1 1 16rem;
		min-width: 0;
	}

	.feedback__select {
		flex: 0 1 14rem;
		min-width: 10rem;
	}

	.feedback__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	a.feedback-card__name:hover {
		text-decoration: underline;
	}

	.feedback-card {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-left: 4px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&--new {
			border-left-color: var(--color-warning);
		}

		&--contacting {
			border-left-color: var(--color-informative);
		}

		&--resolved {
			border-left-color: var(--color-success);
		}

		&__head {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-base);
		}

		&__who {
			display: grid;
			flex: 1 1 14rem;
			gap: 2px;
			min-width: 0;
		}

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
			text-decoration: none;

			&--muted {
				color: var(--color-text--secondary);
				font-weight: 400;
			}
		}

		&__sub {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__state {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-base);
		}

		&__stars {
			display: inline-flex;
			gap: 2px;
			color: var(--color-border);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__star--on {
			color: var(--color-warning);
		}

		&__unrated {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__answers {
			display: grid;
			gap: var(--space-base);
			margin: 0;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--hover);
		}

		&__answer {
			display: grid;
			gap: var(--space-smaller);

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				overflow-wrap: anywhere;
				white-space: pre-wrap;
			}
		}

		&__none {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__actions {
			display: flex;
			align-items: center;
			justify-content: space-between;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__contact,
		&__steps {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__icon {
			display: inline-grid;
			place-items: center;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}

	@media (max-width: 639px) {
		.feedback__select {
			flex: 1 1 100%;
		}

		.feedback-card {
			padding: var(--space-base);
		}
	}
</style>
