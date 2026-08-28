<script lang="ts">
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import { exactTime, previewText } from '$lib/collaboration/format';
	import {
		clientCommunicationHistoryKey,
		conversationCustomerEmail,
		fetchClientCommunicationHistory,
		outboundEmailStatus,
		type ConversationGroup,
		type InboxMessagePage
	} from '$lib/communications/inbox';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import inboundIcon from '@tabler/icons/outline/arrow-down-left.svg?raw';

	// The observed Jobber model (ROADMAP.md § Settled before implementation, Part 5D's approved plan):
	// read-only, newest first, both directions, compact rows, no composer -- sending stays on the client
	// header. `active` gates the fetch so landing on the Details tab never pays for this read; the caller
	// flips it true on tab-active and warms it earlier still via `Tab.onhover`.
	let { clientId, active }: { clientId: string; active: boolean } = $props();

	const historyQuery = createInfiniteQuery(() => ({
		queryKey: clientCommunicationHistoryKey(clientId),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchClientCommunicationHistory(clientId, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: InboxMessagePage) => lastPage.next_cursor ?? undefined,
		enabled: active,
		// Matches the main inbox's own `inboxQuery` window -- every send/resend/read/link path already
		// invalidates this key explicitly, so this only trims refetch-on-refocus noise, not freshness.
		staleTime: 15_000
	}));

	const messages = $derived(historyQuery.data?.pages.flatMap((page) => page.messages ?? []) ?? []);
	// `messages` is newest-first; conversationCustomerEmail expects a group's oldest-first `messages` and
	// walks backward to the most recent real address, skipping a forward row's blank `client_email` (it
	// targets an external address, never the customer's own -- see the helper's own comment in inbox.ts).
	// This component is always scoped to one client, so one address covers every forward row's heading.
	const customerEmail = $derived(
		conversationCustomerEmail({ messages: [...messages].reverse() } as unknown as ConversationGroup)
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if historyQuery.isPending}
	<LoadingSkeleton variant="card" label="Loading communication history" />
{:else if historyQuery.isError}
	<ErrorState description="Communication history could not be loaded. Refresh and try again." />
{:else if messages.length === 0}
	<EmptyState
		icon={messageIcon}
		title="Nothing sent yet"
		description="Emails with this client will be collected here once sending is switched on."
	/>
{:else}
	<ul class="client-history">
		{#each messages as message (message.id)}
			<li
				class="client-history__row"
				class:client-history__row--unread={message.direction === 'inbound' && message.unread}
			>
				<span class="client-history__direction" aria-hidden="true">
					{#if message.direction === 'inbound'}{@html inboundIcon}{/if}
				</span>
				<span class="client-history__copy">
					<span class="client-history__heading">
						<strong
							>{message.direction === 'outbound'
								? message.send_kind === 'forward'
									? customerEmail
									: message.client_email
								: (message.sender_name ?? message.sender_email)}</strong
						>
						{#if message.direction === 'outbound'}
							<Badge size="small" status={outboundEmailStatus(message).tone}
								>{outboundEmailStatus(message).label}</Badge
							>
						{/if}
					</span>
					<span class="client-history__subject">{message.subject}</span>
					<small>{previewText(message.text_content)}</small>
				</span>
				<time class="client-history__time" datetime={message.created_at}
					>{exactTime(message.created_at)}</time
				>
			</li>
		{/each}
	</ul>
	<a class="client-history__open" href={`${resolve('/(app)/communications')}?client=${clientId}`}
		>Open conversation</a
	>
	<ListLoadMore
		hasNextPage={historyQuery.hasNextPage}
		isFetchingNextPage={historyQuery.isFetchingNextPage}
		onLoadMore={() => historyQuery.fetchNextPage()}
		endLabel="That is everything."
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-history {
		display: grid;
		gap: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		overflow: hidden;

		&__row {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface);

			&:first-child {
				border-top: 0;
			}

			&--unread {
				background: var(--color-surface--background--subtle);
			}
		}

		&__direction {
			display: inline-flex;
			flex: 0 0 auto;
			margin-top: 2px;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__copy {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: var(--space-smallest);
		}

		&__heading {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;

			strong {
				overflow: hidden;
				color: var(--color-heading);
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}

		&__subject {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__copy small {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__time {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			white-space: nowrap;
		}

		&__open {
			display: inline-block;
			margin-top: var(--space-base);
			color: var(--color-interactive--subtle);
			font-size: var(--typography--fontSize-small);
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}
	}
</style>
