<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto, replaceState } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Tabs, { type Tab } from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ReviewFeedbackPanel from '$lib/components/reviews/ReviewFeedbackPanel.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		REVIEW_REQUEST_STATUS_LABELS,
		REVIEW_REQUEST_STATUS_TONES,
		REVIEW_REQUEST_STOP_LABELS,
		cancelReviewRequest,
		type ReviewRequestStatus
	} from '$lib/reviews/requests';
	import {
		fetchReviewWorkspaceCounts,
		fetchReviewWorkspaceRequests,
		reviewWorkspaceCountsKey,
		reviewWorkspaceKey,
		reviewWorkspaceRequestsKey,
		type ReviewWorkspacePage,
		type ReviewWorkspaceRequest
	} from '$lib/reviews/workspace';
	import {
		DEFAULT_REVIEW_FEEDBACK_FILTERS,
		fetchReviewFeedback,
		reviewFeedbackKey,
		type ReviewFeedbackPage
	} from '$lib/reviews/feedback';
	import { activityKey } from '$lib/collaboration/api';
	import { jobEventsKey } from '$lib/jobs/api';
	import type { ReviewChannel } from '$lib/reviews/settings';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import googleIcon from '@tabler/icons/outline/brand-google.svg?raw';
	import feedbackIcon from '@tabler/icons/outline/message-heart.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import smsIcon from '@tabler/icons/outline/device-mobile-message.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import cancelIcon from '@tabler/icons/outline/circle-x.svg?raw';

	// Google review campaign Part 5A: the Reviews workspace. One glance answers "who did I ask, and what did
	// they do?"; the table below is the full trail. A Google click is shown as exactly that -- UCRM never
	// claims a review was posted.
	/* eslint-disable svelte/no-navigation-without-resolve -- every href below comes from resolve() in clientHref/jobHref */
	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<ReviewRequestStatus | ''>('');
	let channel = $state<ReviewChannel | ''>('');

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ search: debouncedSearch.trim(), status, channel });
	const hasFilters = $derived(filters.search !== '' || status !== '' || channel !== '');

	const countsQuery = createQuery(() => ({
		queryKey: reviewWorkspaceCountsKey,
		queryFn: fetchReviewWorkspaceCounts,
		staleTime: 30_000
	}));

	// Keyset pagination: each page hands back the cursor for the next one, so a busy business's history
	// costs the same to open as a quiet one's.
	const requestsQuery = createInfiniteQuery(() => ({
		queryKey: reviewWorkspaceRequestsKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchReviewWorkspaceRequests(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: ReviewWorkspacePage) => lastPage.next_cursor ?? undefined
	}));
	const requests = $derived(requestsQuery.data?.pages.flatMap((page) => page.requests) ?? []);
	const refused = $derived((requestsQuery.error as { status?: number } | null)?.status === 403);

	// Whether to offer the setup shortcut: only people who manage review setup can open it.
	const settingsAccessQuery = createQuery<boolean>(() => ({
		queryKey: ['reviews', 'settings-access'],
		queryFn: async () => (await fetch('/api/reviews/settings')).ok,
		staleTime: 5 * 60_000
	}));
	const canManage = $derived(settingsAccessQuery.data === true);

	// Private feedback is only for people who may handle it; the numbers query already says so (a null count
	// means no). While it loads, a link straight to that tab is kept so the page does not flick to Requests.
	const wantsFeedback = $derived(page.url.searchParams.get('tab') === 'feedback');
	const canSeeFeedback = $derived(
		countsQuery.data
			? countsQuery.data.new_feedback !== null
			: wantsFeedback && countsQuery.isPending
	);
	const activeTab = $derived(canSeeFeedback && wantsFeedback ? 'feedback' : 'requests');
	const tabs = $derived.by(() => {
		const list: Tab[] = [{ value: 'requests', label: 'Requests' }];
		if (canSeeFeedback) {
			const waiting = countsQuery.data?.new_feedback ?? 0;
			list.push({
				value: 'feedback',
				label: waiting > 0 ? `Private feedback (${waiting})` : 'Private feedback',
				// Revealed content warms on hover, so the tab is ready by the time it is pressed.
				onhover: () =>
					void queryClient.prefetchInfiniteQuery({
						queryKey: reviewFeedbackKey(DEFAULT_REVIEW_FEEDBACK_FILTERS),
						queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
							fetchReviewFeedback(DEFAULT_REVIEW_FEEDBACK_FILTERS, pageParam),
						initialPageParam: undefined as string | undefined,
						getNextPageParam: (lastPage: ReviewFeedbackPage) => lastPage.next_cursor ?? undefined,
						pages: 1
					})
			});
		}
		return list;
	});
	function selectTab(next: string) {
		const url = new URL(page.url);
		if (next === 'requests') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		replaceState(url, page.state);
	}

	const statusOptions = [
		{ value: '', label: 'Any status' },
		{ value: 'feedback_submitted', label: 'Left private feedback' },
		{ value: 'continued_to_google', label: 'Went to Google' },
		{ value: 'opened', label: 'Opened, no action yet' },
		{ value: 'delivered', label: 'Delivered' },
		{ value: 'sent', label: 'Sent' },
		{ value: 'scheduled', label: 'Scheduled' },
		{ value: 'queued', label: 'Sending' },
		{ value: 'failed', label: 'Not delivered' },
		{ value: 'not_sent', label: 'Not sent' },
		{ value: 'cancelled', label: 'Cancelled' }
	];
	const channelOptions = [
		{ value: '', label: 'Email and text' },
		{ value: 'email', label: 'Email' },
		{ value: 'sms', label: 'Text message' }
	];

	const number = new Intl.NumberFormat();
	function share(part: number, whole: number) {
		return whole > 0 ? `${Math.round((part / whole) * 100)}% of requests` : 'No requests yet';
	}
	const counts = $derived(countsQuery.data);
	const cards = $derived([
		{
			label: 'Asked',
			value: counts ? number.format(counts.asked) : '—',
			note: 'Requests sent, last 30 days',
			icon: sendIcon,
			tone: 'default' as const
		},
		{
			label: 'Opened',
			value: counts ? number.format(counts.opened) : '—',
			note: counts ? share(counts.opened, counts.asked) : 'Looked at the page',
			icon: eyeIcon,
			tone: 'informative' as const
		},
		{
			label: 'Went to Google',
			value: counts ? number.format(counts.went_to_google) : '—',
			note: counts ? share(counts.went_to_google, counts.asked) : 'Tapped through to review',
			icon: googleIcon,
			tone: 'success' as const
		},
		{
			label: 'Private feedback',
			value: counts ? number.format(counts.private_feedback) : '—',
			note:
				counts?.new_feedback && counts.new_feedback > 0
					? `${number.format(counts.new_feedback)} still new`
					: counts
						? share(counts.private_feedback, counts.asked)
						: 'Wrote to you instead',
			icon: feedbackIcon,
			tone: counts?.new_feedback ? ('warning' as const) : ('default' as const)
		}
	]);

	const dateTime = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		hour: 'numeric',
		minute: '2-digit'
	});
	const dateOnly = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' });

	function firstSendTime(request: ReviewWorkspaceRequest) {
		return request.sent_at ?? request.send_at ?? request.created_at;
	}

	// One quiet line under the status: why nothing went, the rating, or where the reminders stand.
	function statusNote(request: ReviewWorkspaceRequest) {
		if (request.status === 'not_sent') {
			return (
				request.stop_detail ??
				(request.stop_reason ? REVIEW_REQUEST_STOP_LABELS[request.stop_reason] : '')
			);
		}
		if (request.status === 'failed') return request.failure_message ?? '';
		const parts: string[] = [];
		const remindersSent = request.messages.filter(
			(message) => message.slot > 0 && message.state !== 'cancelled'
		).length;
		if (remindersSent > 0) {
			parts.push(remindersSent === 1 ? '1 reminder sent' : `${remindersSent} reminders sent`);
		}
		if (request.next_reminder_at && request.status !== 'cancelled') {
			parts.push(`next reminder ${dateOnly.format(new Date(request.next_reminder_at))}`);
		}
		return parts.join(' · ');
	}

	// Annotated: without it TypeScript gives up on the route-id union ("too complex") at the resolve() call.
	function clientHref(request: ReviewWorkspaceRequest): string | null {
		if (!request.client) return null;
		return resolve('/(app)/clients/[id=uuid]', { id: request.client.id });
	}
	function jobHref(request: ReviewWorkspaceRequest): string | null {
		if (!request.job_id) return null;
		return resolve('/(app)/jobs/[id=uuid]', { id: request.job_id });
	}

	const columns: DataTableColumn[] = [
		{ key: 'customer', label: 'Customer' },
		{ key: 'sent', label: 'Sent to' },
		{ key: 'when', label: 'When' },
		{ key: 'status', label: 'What happened' }
	];

	let cancelTarget = $state<ReviewWorkspaceRequest | null>(null);
	let cancelling = $state(false);
	async function confirmCancel() {
		if (!cancelTarget) return;
		cancelling = true;
		try {
			const cancelled = cancelTarget;
			await cancelReviewRequest(cancelled.id);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: reviewWorkspaceKey }),
				// The cancel is recorded on the client's and the job's history.
				...(cancelled.client
					? [
							queryClient.invalidateQueries({
								queryKey: activityKey('client', cancelled.client.id)
							})
						]
					: []),
				...(cancelled.job_id
					? [
							queryClient.invalidateQueries({ queryKey: activityKey('job', cancelled.job_id) }),
							queryClient.invalidateQueries({ queryKey: jobEventsKey(cancelled.job_id) })
						]
					: [])
			]);
			toast.success('Review request cancelled');
			cancelTarget = null;
		} catch (error) {
			toast.error((error as Error).message);
		} finally {
			cancelling = false;
		}
	}

	function menuItems(request: ReviewWorkspaceRequest) {
		const clientLink = clientHref(request);
		const jobLink = jobHref(request);
		const items: { label: string; icon: string; onSelect: () => void; destructive?: boolean }[] =
			[];
		if (clientLink) {
			items.push({ label: 'View client', icon: userIcon, onSelect: () => void goto(clientLink) });
		}
		if (jobLink) {
			items.push({ label: 'View job', icon: briefcaseIcon, onSelect: () => void goto(jobLink) });
		}
		if (request.cancellable) {
			items.push({
				label: 'Cancel request',
				icon: cancelIcon,
				destructive: true,
				onSelect: () => (cancelTarget = request)
			});
		}
		return items;
	}

	function clearFilters() {
		search = '';
		debouncedSearch = '';
		status = '';
		channel = '';
	}
</script>

<svelte:head><title>Reviews · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<!-- eslint-disable svelte/no-navigation-without-resolve -->
	<PageContainer variant="fill">
		<PageHeader
			eyebrow="Reputation"
			title="Reviews"
			description="See who you have asked, what each customer did, and what needs your attention."
		>
			{#snippet actions()}
				{#if canManage}
					<Button variant="secondary" href={resolve('/(app)/reviews/settings')}>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="reviews__button-icon" aria-hidden="true">{@html settingsIcon}</span>
						Review settings
					</Button>
				{/if}
			{/snippet}
		</PageHeader>

		{#if !refused}
			<div class="reviews__stats" aria-label="Last 30 days">
				{#each cards as card (card.label)}
					<KpiCard
						label={card.label}
						value={card.value}
						note={card.note}
						icon={card.icon}
						tone={card.tone}
						variant="compact"
					/>
				{/each}
			</div>
		{/if}

		<div class="reviews__tabs">
			<Tabs {tabs} value={activeTab} onChange={selectTab} label="Reviews views">
				<TabPanel value="requests">
					<section class="reviews__requests" aria-labelledby="reviews-requests-heading">
						{#if !refused}
							<div class="reviews__requests-head">
								<h2 id="reviews-requests-heading">Requests</h2>
								<p>Newest first. Reminders stop by themselves as soon as a customer responds.</p>
							</div>
						{/if}

						{#if !refused}
							<div class="reviews__toolbar">
								<div class="reviews__search">
									<SearchInput
										id="reviews-search"
										bind:value={search}
										placeholder="Search by client name"
									/>
								</div>
								<div class="reviews__select">
									<Select
										id="reviews-status-filter"
										ariaLabel="Filter by status"
										bind:value={status}
										options={statusOptions}
									/>
								</div>
								<div class="reviews__select">
									<Select
										id="reviews-channel-filter"
										ariaLabel="Filter by how it was sent"
										bind:value={channel}
										options={channelOptions}
									/>
								</div>
								{#if hasFilters}
									<Button variant="secondary" onclick={clearFilters}>Clear</Button>
								{/if}
							</div>
						{/if}

						{#if requestsQuery.isPending}
							<LoadingSkeleton variant="table" label="Loading review requests" rows={5} />
						{:else if refused}
							<EmptyState
								icon={starIcon}
								title="You do not have access to Reviews"
								description="Ask an owner or admin to give you review access."
							/>
						{:else if requestsQuery.isError}
							<ErrorState
								description="Review requests could not be loaded. Refresh and try again."
								retry={() => requestsQuery.refetch()}
							/>
						{:else if requests.length === 0}
							<EmptyState
								icon={starIcon}
								title={hasFilters ? 'No matching requests' : 'No review requests yet'}
								description={hasFilters
									? 'Try a different search or clear the filters.'
									: 'Open a finished job and choose Request a review, or turn on automatic asking so every completed job sends one for you.'}
							/>
						{:else}
							<DataTable
								{columns}
								items={requests}
								rowId={(request) => request.id}
								caption="Review requests"
								onRowActivate={(request) => {
									const link = jobHref(request) ?? clientHref(request);
									if (link) void goto(link);
								}}
							>
								{#snippet row(request: ReviewWorkspaceRequest)}
									<th scope="row">
										<div class="reviews-cell">
											<Avatar
												id={request.client?.id ?? request.id}
												name={request.client?.name ?? 'Client removed'}
												size="small"
											/>
											<div class="reviews-cell__copy">
												{#if clientHref(request)}
													<a class="reviews-cell__title" href={clientHref(request)}>
														{request.client?.name}
													</a>
												{:else}
													<span class="reviews-cell__title reviews-cell__title--muted"
														>Client removed</span
													>
												{/if}
												<span class="reviews-cell__sub">
													{#if request.job_number}
														Job #{request.job_number}{request.job_title
															? ` · ${request.job_title}`
															: ''}
													{:else}
														No particular job
													{/if}
												</span>
											</div>
										</div>
									</th>
									<td>
										<div class="reviews-cell">
											<span class="reviews-cell__channel" aria-hidden="true">
												<!-- eslint-disable-next-line svelte/no-at-html-tags -->
												{@html request.channel === 'sms' ? smsIcon : mailIcon}
											</span>
											<div class="reviews-cell__copy">
												<span class="reviews-cell__title">
													{request.channel === 'sms' ? 'Text message' : 'Email'}
												</span>
												<span class="reviews-cell__sub">
													{request.recipient ??
														(request.origin === 'automation' ? 'Automatic' : 'By hand')}
												</span>
											</div>
										</div>
									</td>
									<td>
										<div class="reviews-cell__copy">
											<span class="reviews-cell__title reviews-cell__title--nowrap">
												{dateTime.format(new Date(firstSendTime(request)))}
											</span>
											<span class="reviews-cell__sub">
												{request.origin === 'automation' ? 'Sent automatically' : 'Sent by hand'}
											</span>
										</div>
									</td>
									<td>
										<div class="reviews-cell__copy">
											<StatusBadge status={REVIEW_REQUEST_STATUS_TONES[request.status]}>
												{REVIEW_REQUEST_STATUS_LABELS[request.status]}
												{#if request.rating}· {request.rating}★{/if}
											</StatusBadge>
											{#if statusNote(request)}
												<span class="reviews-cell__sub">{statusNote(request)}</span>
											{/if}
										</div>
									</td>
								{/snippet}
								{#snippet rowActions(request: ReviewWorkspaceRequest)}
									{@const items = menuItems(request)}
									{#if items.length > 0}
										<DropdownMenu
											{items}
											triggerLabel={`Actions for ${request.client?.name ?? 'this request'}`}
										/>
									{/if}
								{/snippet}
								{#snippet footer()}
									<ListLoadMore
										hasNextPage={requestsQuery.hasNextPage}
										isFetchingNextPage={requestsQuery.isFetchingNextPage}
										onLoadMore={() => requestsQuery.fetchNextPage()}
									/>
								{/snippet}
							</DataTable>
						{/if}
					</section>
				</TabPanel>
				{#if canSeeFeedback}
					<TabPanel value="feedback">
						{#if activeTab === 'feedback'}
							<ReviewFeedbackPanel />
						{/if}
					</TabPanel>
				{/if}
			</Tabs>
		</div>
	</PageContainer>
</div>

<ConfirmDialog
	open={cancelTarget !== null}
	title="Cancel this review request?"
	tone="critical"
	destructive
	confirmLabel="Cancel request"
	cancelLabel="Keep it"
	loading={cancelling}
	onConfirm={() => void confirmCancel()}
	onClose={() => (cancelTarget = null)}
>
	The customer's link stops working and any reminders still waiting will not be sent.
</ConfirmDialog>

<style lang="scss">
	.reviews__button-icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.reviews__stats {
		display: grid;
		gap: var(--space-base);
		grid-template-columns: repeat(4, minmax(0, 1fr));
	}

	.reviews__tabs {
		margin-top: var(--space-large);
	}

	.reviews__requests {
		display: grid;
		gap: var(--space-base);
	}

	.reviews__requests-head {
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

	.reviews__toolbar {
		display: flex;
		align-items: stretch;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.reviews__search {
		flex: 1 1 16rem;
		min-width: 0;
	}

	.reviews__select {
		flex: 0 1 13rem;
		min-width: 10rem;
	}

	.reviews-cell {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
	}

	.reviews-cell__copy {
		display: grid;
		gap: 2px;
		min-width: 0;
	}

	.reviews-cell__title {
		color: var(--color-heading);
		font-weight: 600;
		text-decoration: none;

		&--nowrap {
			white-space: nowrap;
		}

		&--muted {
			color: var(--color-text--secondary);
			font-weight: 400;
		}
	}

	a.reviews-cell__title:hover {
		text-decoration: underline;
	}

	.reviews-cell__sub {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.reviews-cell__channel {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-circle);
		background: var(--color-surface--hover);
		color: var(--color-text--secondary);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	@media (max-width: 1023px) {
		.reviews__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.reviews__stats {
			grid-template-columns: minmax(0, 1fr);
		}

		.reviews__select {
			flex: 1 1 100%;
		}
	}
</style>
