<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery, keepPreviousData, useQueryClient } from '@tanstack/svelte-query';
	import SupportConversation from './SupportConversation.svelte';
	import SupportPeople from './SupportPeople.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { relativeTime } from '$lib/collaboration/format';
	import {
		SUPPORT_MAX_LOADED,
		SUPPORT_PAGE_SIZE,
		changeSupportPeople,
		fetchSupportPeople,
		fetchSupportTeamThread,
		fetchSupportTeamThreads,
		fetchSupportThread,
		fetchSupportUnread,
		markSupportThreadRead,
		sendSupportMessage,
		supportPeopleKey,
		supportTeamThreadKey,
		supportTeamThreadPageKey,
		supportTeamThreadsKey,
		supportThreadKey,
		supportThreadPageKey,
		supportUnreadKey,
		type SupportThread
	} from '$lib/support/api';
	import { listenForSupportActivity } from '$lib/support/live';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import backIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// The Uplift Support Messenger: a "Chat with Uplift" button in the bottom-right corner of every signed-in
	// screen, opening the person's own conversation with Uplift (plan §7; Intercom / Help Scout messenger
	// model). It is contractor-to-Uplift only and shares nothing with the customer inbox.
	//
	// Closed, it loads only the unread count for the button's badge: the conversation starts loading when the
	// pointer or keyboard reaches the button, and is cached so reopening is instant. Uplift's replies arrive
	// live (D2): a ping refreshes the badge, and whatever is open too.
	//
	// Who sees what (D3, Zendesk's "My / CC'd / Organization requests"): the person's own conversation opens
	// first. When they may see others — ones they were added to, or every one for an owner or admin — a
	// "Team chats" link opens that list. Each conversation's People panel shows, and for its starter, an owner
	// or an admin changes, who is in it.
	let { userId }: { userId: string } = $props();

	type Screen = { kind: 'own' } | { kind: 'team' } | { kind: 'thread'; id: string };

	const queryClient = useQueryClient();
	let open = $state(false);
	let screen = $state<Screen>({ kind: 'own' });
	let showPeople = $state(false);
	let limit = $state(SUPPORT_PAGE_SIZE);
	let launcherEl = $state<HTMLButtonElement | null>(null);
	let conversation = $state<ReturnType<typeof SupportConversation> | null>(null);

	const teamThreadId = $derived(screen.kind === 'thread' ? screen.id : null);

	const ownQuery = createQuery(() => ({
		queryKey: supportThreadPageKey(userId, limit),
		queryFn: () => fetchSupportThread(limit),
		enabled: open && screen.kind === 'own',
		placeholderData: keepPreviousData
	}));

	const teamListQuery = createQuery(() => ({
		queryKey: supportTeamThreadsKey(userId),
		queryFn: fetchSupportTeamThreads,
		enabled: open && screen.kind === 'team'
	}));

	const teamThreadQuery = createQuery(() => ({
		queryKey: supportTeamThreadPageKey(userId, teamThreadId ?? '', limit),
		queryFn: () => fetchSupportTeamThread(teamThreadId ?? '', limit),
		enabled: open && teamThreadId !== null,
		placeholderData: keepPreviousData
	}));

	const query = $derived(screen.kind === 'thread' ? teamThreadQuery : ownQuery);
	const thread = $derived(screen.kind === 'team' ? undefined : query.data);
	const shownThreadId = $derived(thread?.thread_id ?? null);

	const peopleQuery = createQuery(() => ({
		queryKey: supportPeopleKey(userId, shownThreadId),
		queryFn: () => fetchSupportPeople(shownThreadId ?? ''),
		enabled: open && showPeople && shownThreadId !== null
	}));

	const unreadQuery = createQuery(() => ({
		queryKey: supportUnreadKey(userId),
		queryFn: fetchSupportUnread
	}));
	const unread = $derived(unreadQuery.data?.unread ?? 0);

	// Every conversation, list and people panel sits under the person's thread key, so one ping refreshes
	// what is open and only marks the rest stale.
	$effect(() =>
		listenForSupportActivity(`support-user:${userId}`, () => {
			void queryClient.invalidateQueries({ queryKey: supportUnreadKey(userId) });
			void queryClient.invalidateQueries({ queryKey: supportThreadKey(userId) });
		})
	);

	// Seen means the panel is open on a tab the person is looking at. Each newer message is marked once.
	// A tab opened in the background has not been seen yet.
	let pageVisible = $state(
		typeof document === 'undefined' || document.visibilityState === 'visible'
	);
	let markedThrough: string | null = null;
	$effect(() => {
		const threadId = shownThreadId;
		const newest = thread?.messages.at(-1);
		const key = threadId && newest ? `${threadId}:${newest.created_at}` : null;
		if (
			!open ||
			!pageVisible ||
			showPeople ||
			!key ||
			!threadId ||
			!newest ||
			key === markedThrough
		)
			return;
		// Your own message already counts as read up to itself.
		if (newest.sender_user_id === userId) return;
		markedThrough = key;
		markSupportThreadRead(threadId, newest.created_at)
			.then(() => {
				void queryClient.invalidateQueries({ queryKey: supportUnreadKey(userId) });
				void queryClient.invalidateQueries({
					queryKey: supportTeamThreadsKey(userId),
					refetchType: 'none'
				});
			})
			.catch(() => {
				// The badge stays until the next ping or visit tries again.
				markedThrough = null;
			});
	});

	function warm() {
		void queryClient.prefetchQuery({
			queryKey: supportThreadPageKey(userId, limit),
			queryFn: () => fetchSupportThread(limit),
			staleTime: 30_000
		});
	}

	function warmTeamList() {
		void queryClient.prefetchQuery({
			queryKey: supportTeamThreadsKey(userId),
			queryFn: fetchSupportTeamThreads,
			staleTime: 30_000
		});
	}

	function warmTeamThread(id: string) {
		void queryClient.prefetchQuery({
			queryKey: supportTeamThreadPageKey(userId, id, SUPPORT_PAGE_SIZE),
			queryFn: () => fetchSupportTeamThread(id, SUPPORT_PAGE_SIZE),
			staleTime: 30_000
		});
	}

	function warmPeople() {
		if (!shownThreadId) return;
		const id = shownThreadId;
		void queryClient.prefetchQuery({
			queryKey: supportPeopleKey(userId, id),
			queryFn: () => fetchSupportPeople(id),
			staleTime: 30_000
		});
	}

	async function go(next: Screen) {
		screen = next;
		showPeople = false;
		limit = SUPPORT_PAGE_SIZE;
		if (next.kind === 'team') return;
		await tick();
		conversation?.focusComposer();
	}

	async function openPanel() {
		open = true;
		await tick();
		conversation?.focusComposer();
	}

	async function closePanel() {
		open = false;
		screen = { kind: 'own' };
		showPeople = false;
		await tick();
		launcherEl?.focus();
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Escape') return;
		event.stopPropagation();
		void closePanel();
	}

	async function send(input: { body: string; client_message_id: string }) {
		const target = teamThreadId;
		const message = await sendSupportMessage(target ? { ...input, thread_id: target } : input);
		// Every loaded page of this conversation gains the stored message, so it shows at once.
		const key = target ? supportTeamThreadKey(userId, target) : supportThreadKey(userId);
		queryClient.setQueriesData<SupportThread>({ queryKey: key }, (current) =>
			!current?.messages || current.messages.some((existing) => existing.id === message.id)
				? current
				: { ...current, messages: [...current.messages, message] }
		);
		if (target)
			void queryClient.invalidateQueries({
				queryKey: supportTeamThreadsKey(userId),
				refetchType: 'none'
			});
	}

	async function changePeople(personId: string, adding: boolean) {
		if (!shownThreadId) return;
		await changeSupportPeople(shownThreadId, personId, adding);
		// The grey line is a new message, and the list changed: refresh both.
		await queryClient.invalidateQueries({ queryKey: supportThreadKey(userId) });
	}

	const unreadLabel = $derived(unread > 99 ? '99+' : String(unread));
	const availability = $derived(
		ownQuery.data?.availability_note ?? thread?.availability_note ?? ''
	);
	const teamCount = $derived(ownQuery.data?.team_thread_count ?? 0);
	const title = $derived(
		screen.kind === 'team'
			? 'Team chats'
			: screen.kind === 'thread'
				? `${thread?.started_by_name ?? 'Team member'}'s conversation`
				: 'Uplift Support'
	);
</script>

<svelte:document
	onvisibilitychange={() => (pageVisible = document.visibilityState === 'visible')}
/>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if open}
	<!-- Escape closes the panel from anywhere inside it. -->
	<div
		class="support-messenger"
		tabindex="-1"
		role="dialog"
		aria-modal="false"
		aria-labelledby="support-messenger-title"
		onkeydown={handleKeydown}
	>
		<header class="support-messenger__header">
			{#if screen.kind === 'own'}
				<span class="support-messenger__mark" aria-hidden="true">{@html messageIcon}</span>
			{:else}
				<button
					class="support-messenger__icon-button"
					type="button"
					aria-label={screen.kind === 'thread' ? 'Back to team chats' : 'Back to your conversation'}
					title="Back"
					onclick={() => void go(screen.kind === 'thread' ? { kind: 'team' } : { kind: 'own' })}
				>
					<span aria-hidden="true">{@html backIcon}</span>
				</button>
			{/if}
			<div class="support-messenger__heading">
				<h2 id="support-messenger-title">{title}</h2>
				<p>
					{#if screen.kind === 'team'}
						Conversations with Uplift you can see
					{:else if screen.kind === 'thread'}
						With Uplift Support
					{:else}
						{availability || 'We reply here as soon as we can.'}
					{/if}
				</p>
			</div>
			{#if screen.kind !== 'team' && shownThreadId}
				<button
					class="support-messenger__icon-button"
					class:support-messenger__icon-button--active={showPeople}
					type="button"
					aria-label="People in this conversation"
					aria-pressed={showPeople}
					title="People in this conversation"
					onpointerenter={warmPeople}
					onfocus={warmPeople}
					onclick={() => (showPeople = !showPeople)}
				>
					<span aria-hidden="true">{@html usersIcon}</span>
				</button>
			{/if}
			<button
				class="support-messenger__icon-button"
				type="button"
				aria-label="Close chat"
				title="Close chat"
				onclick={() => void closePanel()}
			>
				<span aria-hidden="true">{@html closeIcon}</span>
			</button>
		</header>

		{#if screen.kind === 'own' && teamCount > 0}
			<button
				class="support-messenger__team-link"
				type="button"
				onpointerenter={warmTeamList}
				onfocus={warmTeamList}
				onclick={() => void go({ kind: 'team' })}
			>
				<span aria-hidden="true">{@html usersIcon}</span>
				<span>Team chats ({teamCount})</span>
				<span class="support-messenger__chevron" aria-hidden="true">{@html chevronIcon}</span>
			</button>
		{/if}

		{#if screen.kind === 'team'}
			<div class="support-messenger__list">
				{#if teamListQuery.isPending}
					<LoadingSkeleton variant="text" rows={4} label="Loading team chats" />
				{:else if teamListQuery.isError}
					<ErrorState
						description="Team chats could not be loaded."
						retry={() => void teamListQuery.refetch()}
					/>
				{:else if teamListQuery.data.threads.length === 0}
					<p class="support-messenger__list-empty">No team chats to show.</p>
				{:else}
					<ul>
						{#each teamListQuery.data.threads as item (item.id)}
							<li>
								<button
									class="support-messenger__row"
									type="button"
									onpointerenter={() => warmTeamThread(item.id)}
									onfocus={() => warmTeamThread(item.id)}
									onclick={() => void go({ kind: 'thread', id: item.id })}
								>
									<span class="support-messenger__row-top">
										<strong>{item.started_by_name}</strong>
										<time datetime={item.last_message_at}>{relativeTime(item.last_message_at)}</time
										>
									</span>
									<span class="support-messenger__row-bottom">
										<span class="support-messenger__preview">
											{item.last_message_sender_kind === 'uplift'
												? 'Uplift: '
												: ''}{item.last_message_preview}
										</span>
										{#if item.unread}
											<span class="support-messenger__dot"
												><span class="support-messenger__sr">New messages</span></span
											>
										{/if}
									</span>
									{#if item.added}
										<span class="support-messenger__added">You were added</span>
									{/if}
								</button>
							</li>
						{/each}
					</ul>
				{/if}
			</div>
		{:else}
			{#if showPeople}
				<SupportPeople
					people={peopleQuery.data}
					loading={peopleQuery.isPending}
					failed={peopleQuery.isError}
					onRetry={() => void peopleQuery.refetch()}
					onChange={changePeople}
					viewerUserId={userId}
				/>
			{/if}
			<div class="support-messenger__body" hidden={showPeople}>
				<SupportConversation
					bind:this={conversation}
					viewer="member"
					viewerUserId={userId}
					conversationKey={teamThreadId ?? 'own'}
					messages={thread?.messages ?? []}
					loading={query.isPending}
					failed={query.isError && !thread}
					onRetry={() => void query.refetch()}
					hasEarlier={(thread?.has_earlier ?? false) && limit < SUPPORT_MAX_LOADED}
					loadingEarlier={query.isPlaceholderData}
					onLoadEarlier={() => (limit = Math.min(limit + SUPPORT_PAGE_SIZE, SUPPORT_MAX_LOADED))}
					onSend={send}
					placeholder="Write to Uplift…"
				>
					{#snippet empty()}
						<div class="support-messenger__welcome">
							<strong>How can we help?</strong>
							<p>
								Ask about your setup, website, Google profile, the CRM or billing. Your message goes
								to the Uplift team — never to your customers.
							</p>
						</div>
					{/snippet}
					{#snippet footnote()}
						Please never send passwords here.
					{/snippet}
				</SupportConversation>
			</div>
		{/if}
	</div>
{:else}
	<button
		class="support-messenger__launcher"
		type="button"
		bind:this={launcherEl}
		aria-haspopup="dialog"
		aria-label={unread > 0 ? `Chat with Uplift, ${unread} unread` : undefined}
		onpointerenter={warm}
		onfocus={warm}
		onclick={() => void openPanel()}
	>
		<span class="support-messenger__launcher-icon" aria-hidden="true">{@html messageIcon}</span>
		<span class="support-messenger__launcher-label">Chat with Uplift</span>
		{#if unread > 0}
			<span class="support-messenger__badge" aria-hidden="true">{unreadLabel}</span>
		{/if}
	</button>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Both sit in the bottom-right corner of the content area. `--support-launcher-clearance` is published
	// by a pinned action bar while one is on screen, so the button rises above it instead of covering Save.
	.support-messenger,
	.support-messenger__launcher {
		position: fixed;
		right: var(--shell-content-right, var(--space-large));
		bottom: calc(var(--shell-edge, var(--space-base)) + var(--space-small));
		z-index: calc(var(--elevation-menu) + 1);
	}

	.support-messenger__launcher {
		bottom: calc(
			var(--shell-edge, var(--space-base)) + var(--space-small) +
				var(--support-launcher-clearance, 0px)
		);
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		min-height: 44px;
		padding: 0 var(--space-base) 0 var(--space-slim);
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		background: var(--color-interactive);
		box-shadow: var(--shadow-high);
		cursor: pointer;
		transition:
			background var(--timing-quick) ease,
			bottom var(--timing-base) ease-out;

		&:hover {
			background: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	// The same red count as the notification bell, on the button's top-right corner.
	.support-messenger__badge {
		position: absolute;
		top: -4px;
		right: -4px;
		min-width: 20px;
		padding: 0 var(--space-smaller);
		border: 2px solid var(--color-surface);
		border-radius: var(--radius-large);
		color: var(--color-text--reverse);
		background: var(--color-critical);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 16px;
		text-align: center;
	}

	.support-messenger__launcher-icon {
		display: inline-flex;

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.support-messenger {
		display: flex;
		flex-direction: column;
		width: min(380px, calc(100vw - (var(--space-base) * 2)));
		height: min(600px, calc(100dvh - 96px));
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-larger);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		overflow: hidden;
	}

	.support-messenger__header {
		display: flex;
		flex: none;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.support-messenger__mark {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-interactive);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.support-messenger__heading {
		flex: 1;
		min-width: 0;

		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			line-height: var(--typography--lineHeight-tight);
		}

		p {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.support-messenger__icon-button {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		padding: 0;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: transparent;
		cursor: pointer;

		span {
			display: inline-flex;
		}

		:global(svg) {
			width: 20px;
			height: 20px;
		}

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&--active {
			color: var(--color-interactive);
			background: var(--color-surface--hover);
		}
	}

	.support-messenger__body {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-height: 0;

		&[hidden] {
			display: none;
		}
	}

	// "Team chats (3)": a quiet row under the header, only when there are others to see.
	.support-messenger__team-link {
		display: flex;
		flex: none;
		align-items: center;
		gap: var(--space-small);
		min-height: 40px;
		padding: 0 var(--space-base);
		border: 0;
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-interactive);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-align: left;
		background: var(--color-surface--background);
		cursor: pointer;

		span {
			display: inline-flex;
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: inset var(--shadow-focus);
		}
	}

	.support-messenger__chevron {
		margin-left: auto;
		color: var(--color-icon);
	}

	.support-messenger__list {
		flex: 1;
		min-height: 0;
		padding: var(--space-small);
		overflow-y: auto;

		ul {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			padding: 0;
			list-style: none;
		}
	}

	.support-messenger__list-empty {
		margin: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		text-align: center;
	}

	.support-messenger__row {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		width: 100%;
		padding: var(--space-small) var(--space-slim);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-text);
		font: inherit;
		text-align: left;
		background: transparent;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.support-messenger__row-top,
	.support-messenger__row-bottom {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
	}

	.support-messenger__row-top {
		justify-content: space-between;

		strong {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		time {
			flex: none;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.support-messenger__preview {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.support-messenger__dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		background: var(--color-interactive);
	}

	.support-messenger__sr {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	.support-messenger__added {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}

	.support-messenger__welcome {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}

		p {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
		}
	}

	// On a phone the conversation takes the whole screen, and the button shrinks to its icon so it covers
	// as little of the page as possible.
	@media (max-width: 767px) {
		.support-messenger {
			inset: 0;
			width: auto;
			height: auto;
			border: 0;
			border-radius: 0;
			z-index: var(--elevation-modal);
		}

		.support-messenger__launcher {
			right: var(--space-base);
			width: 48px;
			min-height: 48px;
			padding: 0;
			justify-content: center;
		}

		.support-messenger__launcher-label {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}
</style>
