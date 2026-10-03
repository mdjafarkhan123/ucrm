<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery, keepPreviousData, useQueryClient } from '@tanstack/svelte-query';
	import SupportConversation from './SupportConversation.svelte';
	import SupportPeople from './SupportPeople.svelte';
	import SupportTopicMenu from './SupportTopicMenu.svelte';
	import SupportTopicPicker from './SupportTopicPicker.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { relativeTime } from '$lib/collaboration/format';
	import {
		SUPPORT_MAX_LOADED,
		SUPPORT_PAGE_SIZE,
		changeSupportPeople,
		changeSupportTopic,
		fetchSupportChats,
		fetchSupportPeople,
		fetchSupportThread,
		fetchSupportUnread,
		markSupportThreadRead,
		presignSupportAttachment,
		sendSupportMessage,
		startSupportThread,
		supportChatsKey,
		supportFileUrls,
		supportKey,
		supportPeopleKey,
		supportThreadKey,
		supportThreadPageKey,
		supportTopicLabel,
		supportUnreadKey,
		type SupportChatRow,
		type SupportOutgoingMessage,
		type SupportThread,
		type SupportTopic
	} from '$lib/support/api';
	import { listenForSupportActivity } from '$lib/support/live';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import backIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// The Uplift Support Messenger: a "Chat with Uplift" button in the bottom-right corner of every signed-in
	// screen (plan §7). It is contractor-to-Uplift only and shares nothing with the customer inbox.
	//
	// Intercom's messenger model (D4a): each question is its own chat with a topic. Opening the messenger lists
	// the person's chats, newest first, with a New message button; someone with no chats yet goes straight to
	// writing one. Closed, it loads only the unread count for the badge: the list starts loading when the
	// pointer or keyboard reaches the button, and is cached so reopening is instant. Uplift's replies arrive
	// live (D2): a ping refreshes the badge, and whatever is open too.
	//
	// Who sees what (D3, Zendesk's "My / CC'd / Organization requests"): when the person may see others' chats
	// — ones they were added to, or every one for an owner or admin — a "Team chats" link opens that list.
	// Each chat's People panel shows, and for its starter, an owner or an admin changes, who is in it.
	let { userId }: { userId: string } = $props();

	type Screen =
		| { kind: 'home' }
		| { kind: 'new' }
		| { kind: 'team' }
		| { kind: 'thread'; id: string; from: 'home' | 'team' };

	const queryClient = useQueryClient();
	let open = $state(false);
	let screen = $state<Screen>({ kind: 'home' });
	let showPeople = $state(false);
	let limit = $state(SUPPORT_PAGE_SIZE);
	let newTopic = $state<SupportTopic>('other');
	let startingChat = $state(false);
	let launcherEl = $state<HTMLButtonElement | null>(null);
	let conversation = $state<ReturnType<typeof SupportConversation> | null>(null);

	const threadId = $derived(screen.kind === 'thread' ? screen.id : null);

	const chatsQuery = createQuery(() => ({
		queryKey: supportChatsKey(userId),
		queryFn: fetchSupportChats,
		enabled: open
	}));
	const chats = $derived(chatsQuery.data);
	const noChatsYet = $derived(chats !== undefined && chats.mine.length === 0);
	// Someone with no chats of their own writes straight away, unless there are team chats to look at.
	const composing = $derived(
		screen.kind === 'new' || (screen.kind === 'home' && noChatsYet && chats?.team.length === 0)
	);

	const threadQuery = createQuery(() => ({
		queryKey: supportThreadPageKey(userId, threadId ?? '', limit),
		queryFn: () => fetchSupportThread(threadId ?? '', limit),
		enabled: open && threadId !== null,
		placeholderData: keepPreviousData
	}));
	const thread = $derived(threadId !== null ? threadQuery.data : undefined);
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

	// Every chat, list and people panel sits under the person's key, so one ping refreshes what is open and
	// only marks the rest stale.
	$effect(() =>
		listenForSupportActivity(`support-user:${userId}`, () => {
			void queryClient.invalidateQueries({ queryKey: supportUnreadKey(userId) });
			void queryClient.invalidateQueries({ queryKey: supportKey(userId) });
		})
	);

	// Seen means the chat is open on a tab the person is looking at. Each newer message is marked once.
	// A tab opened in the background has not been seen yet.
	let pageVisible = $state(
		typeof document === 'undefined' || document.visibilityState === 'visible'
	);
	let markedThrough: string | null = null;
	$effect(() => {
		const id = shownThreadId;
		const newest = thread?.messages.at(-1);
		const key = id && newest ? `${id}:${newest.created_at}` : null;
		if (!open || !pageVisible || showPeople || !key || !id || !newest || key === markedThrough)
			return;
		// Your own message already counts as read up to itself.
		if (newest.sender_user_id === userId) return;
		markedThrough = key;
		markSupportThreadRead(id, newest.created_at)
			.then(() => {
				void queryClient.invalidateQueries({ queryKey: supportUnreadKey(userId) });
				void queryClient.invalidateQueries({
					queryKey: supportChatsKey(userId),
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
			queryKey: supportChatsKey(userId),
			queryFn: fetchSupportChats,
			staleTime: 30_000
		});
	}

	function warmThread(id: string) {
		void queryClient.prefetchQuery({
			queryKey: supportThreadPageKey(userId, id, SUPPORT_PAGE_SIZE),
			queryFn: () => fetchSupportThread(id, SUPPORT_PAGE_SIZE),
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
		if (next.kind === 'new') newTopic = 'other';
		if (next.kind === 'home' || next.kind === 'team') return;
		await tick();
		conversation?.focusComposer();
	}

	function back() {
		void go(
			screen.kind === 'thread' && screen.from === 'team' ? { kind: 'team' } : { kind: 'home' }
		);
	}

	async function openPanel() {
		open = true;
		await tick();
		conversation?.focusComposer();
	}

	async function closePanel() {
		open = false;
		screen = { kind: 'home' };
		showPeople = false;
		newTopic = 'other';
		await tick();
		launcherEl?.focus();
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Escape') return;
		event.stopPropagation();
		void closePanel();
	}

	// The first message makes the chat, which then opens with that message already in it. Send stays off
	// until it is saved, so a second message can never start a second chat.
	async function startChat(input: SupportOutgoingMessage) {
		startingChat = true;
		try {
			const topic = newTopic;
			const message = await startSupportThread({ ...input, topic });
			const seeded: SupportThread = {
				thread_id: message.thread_id,
				topic,
				can_change_topic: true,
				messages: [message],
				has_earlier: false,
				availability_note: chats?.availability_note ?? '',
				started_by_name: null,
				status: 'open'
			};
			queryClient.setQueryData(
				supportThreadPageKey(userId, message.thread_id, SUPPORT_PAGE_SIZE),
				seeded
			);
			void queryClient.invalidateQueries({ queryKey: supportChatsKey(userId) });
			await go({ kind: 'thread', id: message.thread_id, from: 'home' });
		} finally {
			startingChat = false;
		}
	}

	async function send(input: SupportOutgoingMessage) {
		const target = threadId;
		if (!target) return startChat(input);
		const message = await sendSupportMessage({ ...input, thread_id: target });
		// Every loaded page of this chat gains the stored message, so it shows at once.
		queryClient.setQueriesData<SupportThread>(
			{ queryKey: supportThreadKey(userId, target) },
			(current) =>
				!current?.messages || current.messages.some((existing) => existing.id === message.id)
					? current
					: { ...current, messages: [...current.messages, message] }
		);
		void queryClient.invalidateQueries({
			queryKey: supportChatsKey(userId),
			refetchType: 'none'
		});
	}

	async function changePeople(personId: string, adding: boolean) {
		if (!shownThreadId) return;
		await changeSupportPeople(shownThreadId, personId, adding);
		// The grey line is a new message, and the list changed: refresh both.
		await queryClient.invalidateQueries({ queryKey: supportKey(userId) });
	}

	async function changeTopic(topic: SupportTopic) {
		if (!shownThreadId) return;
		await changeSupportTopic(shownThreadId, topic);
		// The grey line is a new message, and both lists show the topic.
		await queryClient.invalidateQueries({ queryKey: supportKey(userId) });
	}

	function preview(item: SupportChatRow) {
		return `${item.last_message_sender_kind === 'uplift' ? 'Uplift: ' : ''}${item.last_message_preview}`;
	}

	const unreadLabel = $derived(unread > 99 ? '99+' : String(unread));
	const availability = $derived(chats?.availability_note ?? thread?.availability_note ?? '');
	const teamCount = $derived(chats?.team.length ?? 0);
	const title = $derived(
		screen.kind === 'team'
			? 'Team chats'
			: screen.kind === 'thread' && thread?.started_by_name
				? `${thread.started_by_name}'s chat`
				: composing && screen.kind === 'new'
					? 'New message'
					: 'Uplift Support'
	);
</script>

<svelte:document
	onvisibilitychange={() => (pageVisible = document.visibilityState === 'visible')}
/>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet chatRow(item: SupportChatRow, from: 'home' | 'team')}
	<li>
		<button
			class="support-messenger__row"
			type="button"
			onpointerenter={() => warmThread(item.id)}
			onfocus={() => warmThread(item.id)}
			onclick={() => void go({ kind: 'thread', id: item.id, from })}
		>
			<span class="support-messenger__row-top">
				{#if from === 'team'}
					<strong>{item.started_by_name}</strong>
					<span class="support-messenger__topic">{supportTopicLabel(item.topic)}</span>
				{:else}
					<strong>{supportTopicLabel(item.topic)}</strong>
				{/if}
				{#if item.status === 'solved'}
					<span class="support-messenger__solved">Solved</span>
				{/if}
				<time datetime={item.last_message_at}>{relativeTime(item.last_message_at)}</time>
			</span>
			<span class="support-messenger__row-bottom">
				<span class="support-messenger__preview">{preview(item)}</span>
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
{/snippet}

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
			{#if screen.kind === 'home'}
				<span class="support-messenger__mark" aria-hidden="true">{@html messageIcon}</span>
			{:else}
				<button
					class="support-messenger__icon-button"
					type="button"
					aria-label={screen.kind === 'thread' && screen.from === 'team'
						? 'Back to team chats'
						: 'Back to your chats'}
					title="Back"
					onclick={back}
				>
					<span aria-hidden="true">{@html backIcon}</span>
				</button>
			{/if}
			<div class="support-messenger__heading">
				<h2 id="support-messenger-title">{title}</h2>
				{#if screen.kind === 'thread' && thread}
					<div class="support-messenger__subline">
						<SupportTopicMenu
							topic={thread.topic}
							canChange={thread.can_change_topic}
							onChange={changeTopic}
						/>
						{#if thread.status === 'solved'}
							<span class="support-messenger__solved">Solved</span>
						{/if}
						{#if thread.started_by_name}<span>With Uplift Support</span>{/if}
					</div>
				{:else}
					<p>
						{#if screen.kind === 'team'}
							Chats with Uplift you can see
						{:else}
							{availability || 'We reply here as soon as we can.'}
						{/if}
					</p>
				{/if}
			</div>
			{#if screen.kind === 'thread' && shownThreadId}
				<button
					class="support-messenger__icon-button"
					class:support-messenger__icon-button--active={showPeople}
					type="button"
					aria-label="People in this chat"
					aria-pressed={showPeople}
					title="People in this chat"
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

		{#if screen.kind === 'home' && teamCount > 0}
			<button
				class="support-messenger__team-link"
				type="button"
				onclick={() => void go({ kind: 'team' })}
			>
				<span aria-hidden="true">{@html usersIcon}</span>
				<span>Team chats ({teamCount})</span>
				<span class="support-messenger__chevron" aria-hidden="true">{@html chevronIcon}</span>
			</button>
		{/if}

		{#if composing || screen.kind === 'thread'}
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
					conversationKey={threadId ?? 'new'}
					messages={thread?.messages ?? []}
					loading={threadId !== null && threadQuery.isPending}
					failed={threadId !== null && threadQuery.isError && !thread}
					onRetry={() => void threadQuery.refetch()}
					hasEarlier={(thread?.has_earlier ?? false) && limit < SUPPORT_MAX_LOADED}
					loadingEarlier={threadQuery.isPlaceholderData}
					onLoadEarlier={() => (limit = Math.min(limit + SUPPORT_PAGE_SIZE, SUPPORT_MAX_LOADED))}
					onSend={send}
					presignAttachment={presignSupportAttachment}
					fileUrls={supportFileUrls}
					blockedReason={startingChat ? 'Starting your chat…' : ''}
					placeholder={!threadId
						? 'Ask Uplift a question…'
						: thread?.status === 'solved'
							? 'Write again to reopen this chat…'
							: 'Write to Uplift…'}
				>
					{#snippet empty()}
						<div class="support-messenger__welcome">
							<strong>How can we help?</strong>
							<p>
								Each question gets its own chat. Your message goes to the Uplift team — never to
								your customers.
							</p>
						</div>
						<SupportTopicPicker bind:value={newTopic} disabled={startingChat} />
					{/snippet}
					{#snippet footnote()}
						Please never send passwords here.
					{/snippet}
				</SupportConversation>
			</div>
		{:else}
			<div class="support-messenger__list">
				{#if chatsQuery.isPending}
					<LoadingSkeleton variant="text" rows={4} label="Loading your chats" />
				{:else if chatsQuery.isError}
					<ErrorState
						description="Your chats could not be loaded."
						retry={() => void chatsQuery.refetch()}
					/>
				{:else if screen.kind === 'team'}
					{#if chatsQuery.data.team.length === 0}
						<p class="support-messenger__list-empty">No team chats to show.</p>
					{:else}
						<ul>
							{#each chatsQuery.data.team as item (item.id)}
								{@render chatRow(item, 'team')}
							{/each}
						</ul>
					{/if}
				{:else if chatsQuery.data.mine.length === 0}
					<p class="support-messenger__list-empty">You have not written to Uplift yet.</p>
				{:else}
					<ul>
						{#each chatsQuery.data.mine as item (item.id)}
							{@render chatRow(item, 'home')}
						{/each}
					</ul>
				{/if}
			</div>
			{#if screen.kind === 'home'}
				<div class="support-messenger__new">
					<Button variant="primary" fullWidth onclick={() => void go({ kind: 'new' })}>
						<span class="support-messenger__new-icon" aria-hidden="true">{@html plusIcon}</span>
						New message
					</Button>
				</div>
			{/if}
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
		// A pill, not an ellipse: the circle radius is a percentage, which turns a wide button into an egg.
		border-radius: var(--radius-larger);
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
			margin-left: auto;
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

	.support-messenger__subline {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
		margin-top: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	// A team chat's topic beside the person's name, the same pill as a chat header's.
	.support-messenger__topic {
		flex: none;
		padding: 3px var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 1;
	}

	// Uplift marked the chat solved (D5a). The same pill, in green; writing again reopens it.
	.support-messenger__solved {
		flex: none;
		padding: 3px var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 1;
	}

	// "New message" stays at the foot of the list, however long it grows.
	.support-messenger__new {
		flex: none;
		padding: var(--space-slim) var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}

	.support-messenger__new-icon {
		display: inline-flex;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
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
