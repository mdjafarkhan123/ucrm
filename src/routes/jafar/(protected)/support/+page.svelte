<script lang="ts">
	import { createQuery, keepPreviousData, useQueryClient } from '@tanstack/svelte-query';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SupportConversation from '$lib/components/support/SupportConversation.svelte';
	import SupportSettingsDialog from '$lib/components/support/SupportSettingsDialog.svelte';
	import SupportPeople from '$lib/components/support/SupportPeople.svelte';
	import SupportTopicMenu from '$lib/components/support/SupportTopicMenu.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { relativeTime } from '$lib/collaboration/format';
	import { urlParam } from '$lib/url-param.svelte';
	import {
		SUPPORT_MAX_LOADED,
		SUPPORT_PAGE_SIZE,
		SUPPORT_TOPICS,
		changeSupportInboxPeople,
		changeSupportInboxTopic,
		fetchSupportInbox,
		fetchSupportInboxPeople,
		fetchSupportInboxThread,
		jafarSupportFileUrls,
		jafarSupportPeopleKey,
		jafarSupportInboxKey,
		jafarSupportInboxPageKey,
		jafarSupportKey,
		jafarSupportThreadKey,
		jafarSupportThreadPageKey,
		markSupportInboxThreadRead,
		presignSupportReplyAttachment,
		replyToSupportThread,
		supportTopicLabel,
		type SupportInbox,
		type SupportInboxThreadDetail,
		type SupportOutgoingMessage,
		type SupportSettings,
		type SupportTopic
	} from '$lib/support/api';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';

	// The Support Inbox: every contractor team member's conversation with Uplift (plan §7). It is the
	// platform's own inbox and never shows, or shows in, a contractor's customer inbox.
	const queryClient = useQueryClient();

	// The open conversation lives in the address, so a refresh or a shared link lands on it.
	const selected = urlParam('thread', '');
	const selectedId = $derived(selected.current || null);
	// The topic filter (D4a) lives there too.
	const topicParam = urlParam('topic', '');
	const topicFilter = $derived(
		(SUPPORT_TOPICS.find((item) => item.value === topicParam.current)?.value ??
			null) as SupportTopic | null
	);
	const topicOptions = [
		{ value: '', label: 'All topics' },
		...SUPPORT_TOPICS.map((item) => ({ value: item.value, label: item.label }))
	];

	let inboxLimit = $state(SUPPORT_PAGE_SIZE);
	let threadLimit = $state(SUPPORT_PAGE_SIZE);
	let settingsOpen = $state(false);
	// The People panel (D3): who is in the open conversation, and adding or removing a teammate.
	let showPeople = $state(false);

	const people = createQuery(() => ({
		queryKey: jafarSupportPeopleKey(selectedId),
		queryFn: () => fetchSupportInboxPeople(selectedId as string),
		enabled: showPeople && selectedId !== null
	}));

	function warmPeople() {
		if (!selectedId) return;
		const threadId = selectedId;
		void queryClient.prefetchQuery({
			queryKey: jafarSupportPeopleKey(threadId),
			queryFn: () => fetchSupportInboxPeople(threadId),
			staleTime: 10_000
		});
	}

	async function changePeople(userId: string, adding: boolean) {
		if (!selectedId) return;
		await changeSupportInboxPeople(selectedId, userId, adding);
		// The grey line is a new message in the conversation; the list changed too.
		await queryClient.invalidateQueries({ queryKey: jafarSupportThreadKey(selectedId) });
	}

	async function changeTopic(topic: SupportTopic) {
		if (!selectedId) return;
		await changeSupportInboxTopic(selectedId, topic);
		// The grey line is a new message, and the list shows and filters by the topic.
		await queryClient.invalidateQueries({ queryKey: jafarSupportKey });
	}

	// New messages arrive live: the /jafar layout listens for them and refreshes these queries (D2).
	const inbox = createQuery(() => ({
		queryKey: jafarSupportInboxPageKey(inboxLimit, topicFilter),
		queryFn: () => fetchSupportInbox(inboxLimit, topicFilter),
		placeholderData: keepPreviousData
	}));

	const thread = createQuery(() => ({
		queryKey: jafarSupportThreadPageKey(selectedId, threadLimit),
		queryFn: () => fetchSupportInboxThread(selectedId as string, threadLimit),
		enabled: selectedId !== null,
		placeholderData: keepPreviousData
	}));

	// An unread conversation becomes read once it is open on a tab Jafar is looking at, up to its newest
	// message. Each newer message is marked once.
	// A tab opened in the background has not been seen yet.
	let pageVisible = $state(
		typeof document === 'undefined' || document.visibilityState === 'visible'
	);
	let markedThrough: string | null = null;
	$effect(() => {
		const detail = thread.data;
		if (!pageVisible || !detail || detail.thread.id !== selectedId || !detail.thread.unread) return;
		const newest = detail.messages.at(-1);
		if (!newest || newest.created_at === markedThrough) return;
		markedThrough = newest.created_at;
		markSupportInboxThreadRead(detail.thread.id, newest.created_at)
			.then(() => queryClient.invalidateQueries({ queryKey: jafarSupportKey }))
			.catch(() => {
				markedThrough = null;
			});
	});

	const threads = $derived(inbox.data?.threads ?? []);
	const settings = $derived(inbox.data?.settings ?? null);
	const waitingCount = $derived(
		threads.filter((item) => item.last_message_sender_kind === 'member').length
	);
	// The header of the open conversation: from the thread itself, or from its list row while that loads.
	const current = $derived(
		(thread.data?.thread.id === selectedId ? thread.data?.thread : null) ??
			threads.find((item) => item.id === selectedId) ??
			null
	);
	const needsName = $derived(settings !== null && settings.responder_name === '');

	// A conversation starts loading when the pointer or keyboard reaches its row.
	function warm(threadId: string) {
		void queryClient.prefetchQuery({
			queryKey: jafarSupportThreadPageKey(threadId, SUPPORT_PAGE_SIZE),
			queryFn: () => fetchSupportInboxThread(threadId, SUPPORT_PAGE_SIZE),
			staleTime: 10_000
		});
	}

	function openThread(threadId: string) {
		threadLimit = SUPPORT_PAGE_SIZE;
		showPeople = false;
		selected.set(threadId);
	}

	async function reply(input: SupportOutgoingMessage) {
		if (!selectedId) return;
		const threadId = selectedId;
		const message = await replyToSupportThread(threadId, input);
		queryClient.setQueriesData<SupportInboxThreadDetail>(
			{ queryKey: jafarSupportThreadKey(threadId) },
			(detail) =>
				!detail || detail.messages.some((existing) => existing.id === message.id)
					? detail
					: { ...detail, messages: [...detail.messages, message] }
		);
		// The list row's preview, order and "waiting" mark all change with a reply.
		void queryClient.invalidateQueries({ queryKey: jafarSupportInboxKey });
	}

	function settingsSaved(next: SupportSettings) {
		queryClient.setQueriesData<SupportInbox>({ queryKey: jafarSupportInboxKey }, (data) =>
			data ? { ...data, settings: next } : data
		);
		settingsOpen = false;
	}
</script>

<svelte:head><title>Support Inbox · Control Room</title></svelte:head>
<svelte:document
	onvisibilitychange={() => (pageVisible = document.visibilityState === 'visible')}
/>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="support-inbox">
	<PageHeader
		eyebrow="Platform owner"
		title="Support Inbox"
		description="Messages contractors send from Chat with Uplift. Their customers never see these."
	>
		{#snippet actions()}
			<Button variant="secondary" disabled={!settings} onclick={() => (settingsOpen = true)}>
				<span class="support-inbox__button-icon" aria-hidden="true">{@html settingsIcon}</span>
				Support settings
			</Button>
		{/snippet}
	</PageHeader>

	{#if needsName}
		<Banner type="warning">
			Add the name clients see on your replies before you answer a message.
			{#snippet action()}
				<Button size="small" onclick={() => (settingsOpen = true)}>Add your name</Button>
			{/snippet}
		</Banner>
	{/if}

	<div class="support-inbox__frame" class:support-inbox__frame--thread-open={selectedId !== null}>
		<section class="support-inbox__list" aria-label="Conversations">
			<header class="support-inbox__list-header">
				<h2>Conversations</h2>
				{#if waitingCount > 0}
					<Badge status="warning" size="small">{waitingCount} waiting for you</Badge>
				{/if}
				<Select
					id="support-inbox-topic"
					ariaLabel="Filter by topic"
					class="support-inbox__topic-filter"
					value={topicFilter ?? ''}
					options={topicOptions}
					onchange={(value) => {
						inboxLimit = SUPPORT_PAGE_SIZE;
						topicParam.set(value);
					}}
				/>
			</header>

			{#if inbox.isPending}
				<div class="support-inbox__pad"><LoadingSkeleton variant="text" rows={5} /></div>
			{:else if inbox.isError && !inbox.data}
				<ErrorState
					description="The Support Inbox could not be loaded."
					retry={() => void inbox.refetch()}
				/>
			{:else if threads.length === 0 && topicFilter}
				<EmptyState
					icon={messagesIcon}
					title={`No ${supportTopicLabel(topicFilter)} chats`}
					description="Choose All topics to see every conversation."
				/>
			{:else if threads.length === 0}
				<EmptyState
					icon={messagesIcon}
					title="No messages yet"
					description="When a contractor writes from Chat with Uplift, the conversation appears here."
				/>
			{:else}
				<ul class="support-inbox__threads">
					{#each threads as item (item.id)}
						{@const waiting = item.last_message_sender_kind === 'member'}
						<li>
							<button
								class="support-inbox__thread"
								class:support-inbox__thread--active={item.id === selectedId}
								class:support-inbox__thread--unread={item.unread}
								type="button"
								aria-current={item.id === selectedId ? 'true' : undefined}
								onpointerenter={() => warm(item.id)}
								onfocus={() => warm(item.id)}
								onclick={() => openThread(item.id)}
							>
								<span class="support-inbox__thread-top">
									<strong
										>{#if item.unread}<span class="support-inbox__hidden">Unread: </span>{/if}{item
											.organization.name}</strong
									>
									<time datetime={item.last_message_at}>{relativeTime(item.last_message_at)}</time>
								</span>
								<span class="support-inbox__thread-member">
									<span>{item.member_name}</span>
									<span class="support-inbox__thread-topic">{supportTopicLabel(item.topic)}</span>
								</span>
								<span class="support-inbox__thread-bottom">
									<span class="support-inbox__thread-preview"
										>{waiting ? '' : 'You: '}{item.last_message_preview}</span
									>
									{#if waiting}
										<span class="support-inbox__thread-dot" aria-label="Waiting for your reply"
										></span>
									{/if}
								</span>
							</button>
						</li>
					{/each}
				</ul>
				{#if inbox.data?.has_more && inboxLimit < SUPPORT_MAX_LOADED}
					<div class="support-inbox__more">
						<Button
							variant="tertiary"
							size="small"
							loading={inbox.isPlaceholderData}
							onclick={() =>
								(inboxLimit = Math.min(inboxLimit + SUPPORT_PAGE_SIZE, SUPPORT_MAX_LOADED))}
							>Show more conversations</Button
						>
					</div>
				{/if}
			{/if}
		</section>

		<section class="support-inbox__conversation" aria-label="Open conversation">
			{#if selectedId === null}
				<EmptyState
					icon={messagesIcon}
					title="Choose a conversation"
					description="Pick one on the left to read it and reply."
				/>
			{:else if thread.isError && !thread.data}
				<header class="support-inbox__conversation-header">
					<button
						class="support-inbox__back"
						type="button"
						aria-label="Back to conversations"
						onclick={() => selected.set('')}
					>
						<span aria-hidden="true">{@html arrowLeftIcon}</span>
					</button>
				</header>
				<ErrorState
					description="This conversation could not be loaded. It may no longer exist."
					retry={() => void thread.refetch()}
				/>
			{:else}
				<header class="support-inbox__conversation-header">
					<button
						class="support-inbox__back"
						type="button"
						aria-label="Back to conversations"
						onclick={() => selected.set('')}
					>
						<span aria-hidden="true">{@html arrowLeftIcon}</span>
					</button>
					<div class="support-inbox__conversation-title">
						{#if current}
							<h2>{current.organization.name}</h2>
							<p>
								<span>{current.member_name}</span>
								<SupportTopicMenu topic={current.topic} canChange onChange={changeTopic} />
							</p>
						{:else}
							<LoadingSkeleton variant="heading" label="Loading conversation" />
						{/if}
					</div>
					{#if current}
						<Button
							variant="tertiary"
							size="small"
							onhover={warmPeople}
							onclick={() => (showPeople = !showPeople)}
							>{showPeople ? 'Conversation' : 'People'}</Button
						>
						<Button
							variant="tertiary"
							size="small"
							href={`/jafar/organizations/${current.organization.id}`}>Open organization</Button
						>
					{/if}
				</header>
				{#if showPeople}
					<SupportPeople
						people={people.data}
						loading={people.isPending}
						failed={people.isError}
						onRetry={() => void people.refetch()}
						onChange={changePeople}
					/>
				{/if}
				<div class="support-inbox__conversation-body" hidden={showPeople}>
					<SupportConversation
						viewer="uplift"
						conversationKey={selectedId}
						messages={thread.data?.thread.id === selectedId ? thread.data.messages : []}
						loading={thread.isPending || thread.data?.thread.id !== selectedId}
						hasEarlier={(thread.data?.has_earlier ?? false) && threadLimit < SUPPORT_MAX_LOADED}
						loadingEarlier={thread.isPlaceholderData}
						onLoadEarlier={() =>
							(threadLimit = Math.min(threadLimit + SUPPORT_PAGE_SIZE, SUPPORT_MAX_LOADED))}
						onSend={reply}
						presignAttachment={(file) => presignSupportReplyAttachment(selectedId ?? '', file)}
						fileUrls={jafarSupportFileUrls}
						placeholder="Write a reply…"
						blockedReason={needsName ? 'Add your name in Support settings before replying.' : ''}
					>
						{#snippet footnote()}
							{settings?.responder_name
								? `Clients see this as Uplift Support · ${settings.responder_name}.`
								: ''}
						{/snippet}
					</SupportConversation>
				</div>
			{/if}
		</section>
	</div>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

{#if settingsOpen && settings}
	<SupportSettingsDialog
		{settings}
		onClose={() => (settingsOpen = false)}
		onSaved={settingsSaved}
	/>
{/if}

<style lang="scss">
	.support-inbox {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		height: 100%;
		min-height: 0;

		// PageHeader carries its own bottom margin; the column gap already spaces what follows.
		:global(.page-header) {
			margin-bottom: 0;
		}

		&__button-icon {
			display: inline-flex;
			width: 1.8rem;
			height: 1.8rem;

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}

		&__frame {
			display: grid;
			flex: 1;
			grid-template-columns: minmax(260px, 340px) minmax(0, 1fr);
			min-height: 420px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			overflow: hidden;
		}

		&__list {
			display: flex;
			flex-direction: column;
			min-height: 0;
			border-right: var(--border-base) solid var(--color-border);
			overflow-y: auto;
		}

		&__list-header {
			display: flex;
			flex: none;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			min-height: 56px;
			padding: var(--space-small) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
			}

			// The topic filter sits at the end of the row, after the "waiting" badge.
			:global(.support-inbox__topic-filter) {
				width: 148px;
				margin-left: auto;
			}
		}

		&__pad {
			padding: var(--space-base);
		}

		&__threads {
			margin: 0;
			padding: 0;
			list-style: none;

			li + li {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__thread {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			width: 100%;
			padding: var(--space-slim) var(--space-base);
			border: 0;
			color: inherit;
			font: inherit;
			text-align: left;
			background: transparent;
			cursor: pointer;
			transition: background var(--timing-quick) ease;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: inset 0 0 0 2px var(--color-focus);
			}

			&--active,
			&--active:hover {
				background: var(--color-surface--active);
			}
		}

		&__thread-top,
		&__thread-bottom {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			min-width: 0;
		}

		&__thread-top {
			strong {
				min-width: 0;
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			time {
				flex: none;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__thread-member {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			> span:first-child {
				min-width: 0;
				overflow: hidden;
				text-overflow: ellipsis;
			}
		}

		&__thread-topic {
			flex: none;
			padding: 3px var(--space-small);
			border-radius: var(--radius-circle);
			color: var(--color-heading);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			line-height: 1;
		}

		&__thread-member,
		&__thread-preview {
			min-width: 0;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		// Unread reads like an unread email: the name and the latest words stand out until opened.
		&__thread--unread {
			.support-inbox__thread-top strong {
				font-weight: 700;
			}

			.support-inbox__thread-preview {
				color: var(--color-heading);
				font-weight: 500;
			}
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&__thread-dot {
			flex: none;
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-warning);
		}

		&__more {
			display: flex;
			justify-content: center;
			padding: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__conversation {
			display: flex;
			flex-direction: column;
			min-width: 0;
			min-height: 0;
		}

		&__conversation-body {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-height: 0;

			&[hidden] {
				display: none;
			}
		}

		&__conversation-header {
			display: flex;
			flex: none;
			align-items: center;
			gap: var(--space-small);
			min-height: 56px;
			padding: var(--space-small) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		&__conversation-title {
			flex: 1;
			min-width: 0;

			h2 {
				margin: 0;
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			p {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__back {
			display: none;
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
		}
	}

	// On a narrow screen the list and the open conversation take turns.
	@media (max-width: 899px) {
		.support-inbox {
			&__frame {
				grid-template-columns: 1fr;
			}

			&__list {
				border-right: 0;
			}

			&__conversation {
				display: none;
			}

			&__frame--thread-open &__list {
				display: none;
			}

			&__frame--thread-open &__conversation {
				display: flex;
			}

			&__back {
				display: grid;
			}
		}
	}
</style>
