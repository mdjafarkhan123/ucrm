<script lang="ts">
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import ChannelMark, { CHANNEL_LABELS, type InboxChannel } from './ChannelMark.svelte';
	import { initials, previewText } from '$lib/collaboration/format';
	import {
		isUnknownCustomer,
		isWebsiteChatMessage,
		type ConversationGroup,
		type InboxView
	} from '$lib/communications/inbox';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import pencilIcon from '@tabler/icons/outline/edit.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import filterIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';
	import userRoundIcon from '@tabler/icons/outline/user.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The inbox's list card (design skill inbox.md, List): who is writing, newest first, with the ones waiting on
	// the team gathered under "Needs reply". Search, Team / Mine and the channel lanes narrow it down.
	let {
		groups,
		selectedKey,
		view = $bindable('team'),
		canViewTeam,
		search = $bindable(''),
		emptyView,
		onSelect,
		onNew,
		onNewHover
	}: {
		groups: ConversationGroup[];
		selectedKey: string | null;
		view?: InboxView;
		canViewTeam: boolean;
		/** The search the list was loaded with; the box keeps its own draft until it is submitted. */
		search?: string;
		/** Which list the server answered with, for the empty state's wording. */
		emptyView: InboxView;
		onSelect: (group: ConversationGroup) => void;
		onNew: () => void;
		onNewHover: () => void;
	} = $props();

	const LANES: InboxChannel[] = ['messenger', 'sms', 'email', 'website_chat'];

	let searchDraft = $state(search);
	let lane = $state<InboxChannel | 'all'>('all');
	let unreadOnly = $state(false);

	const visibleGroups = $derived(
		groups.filter(
			(group) =>
				(!unreadOnly || group.unreadCount > 0) &&
				(lane === 'all' || group.messages.some((message) => message.channel === lane))
		)
	);
	// Customers waiting on the team come first (Front's "Unreplied", Intercom's "waiting on you"): the customer
	// spoke last, or something is still unread. Opening a conversation never moves it out -- only an answer does.
	const waitingOnTeam = (group: ConversationGroup) => group.awaitingReply || group.unreadCount > 0;
	const needsReply = $derived(visibleGroups.filter(waitingOnTeam));
	const earlier = $derived(visibleGroups.filter((group) => !waitingOnTeam(group)));
	const orderedGroups = $derived([...needsReply, ...earlier]);

	// The list is one Tab stop, not one per row -- with hundreds of conversations a keyboard user would otherwise
	// Tab through every one to reach the timeline. The stop is the row last focused, else the open conversation,
	// else the first row; arrow keys move between the rest.
	let focusedRowKey = $state<string | null>(null);
	const rowTabStopKey = $derived.by(() => {
		for (const key of [focusedRowKey, selectedKey]) {
			if (key && orderedGroups.some((group) => group.key === key)) return key;
		}
		return orderedGroups[0]?.key ?? null;
	});

	function handleRowKeydown(event: KeyboardEvent) {
		if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
		const list = (event.currentTarget as HTMLElement).closest('.inbox-list__rows');
		if (!list) return;
		const rows = Array.from(list.querySelectorAll<HTMLButtonElement>('.inbox-list__row'));
		const currentIndex = rows.indexOf(event.currentTarget as HTMLButtonElement);
		if (currentIndex === -1) return;
		event.preventDefault();
		const nextIndex =
			event.key === 'Home'
				? 0
				: event.key === 'End'
					? rows.length - 1
					: event.key === 'ArrowDown'
						? Math.min(currentIndex + 1, rows.length - 1)
						: Math.max(currentIndex - 1, 0);
		rows[nextIndex]?.focus();
	}

	function rowPreview(group: ConversationGroup) {
		const latest = group.latest;
		if (isWebsiteChatMessage(latest)) return previewText(latest.body);
		// An email's subject says more in a list than its first line does; a text or Messenger message has none.
		if (latest.channel === 'email' && latest.subject && latest.direction === 'inbound')
			return latest.subject;
		return previewText(latest.text_content);
	}

	// "You:" or "Auto:" ahead of the preview when the business spoke last, so the list says who is waiting.
	function rowPrefix(group: ConversationGroup): string | null {
		const latest = group.latest;
		if (isWebsiteChatMessage(latest)) {
			if (latest.sender_type === 'staff') return 'You: ';
			return latest.sender_type === 'automation' ? 'Auto: ' : null;
		}
		if (latest.direction !== 'outbound') return null;
		return latest.send_kind === 'automated' ? 'Auto: ' : 'You: ';
	}

	// The list's own short time: the hour for today, then the day, so a glance tells how stale a row is.
	function formatListTime(value: string) {
		const date = new Date(value);
		const now = new Date();
		if (date.toDateString() === now.toDateString()) {
			return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(
				date
			);
		}
		if (date.toDateString() === new Date(Date.now() - 86_400_000).toDateString())
			return 'Yesterday';
		const withinWeek = now.getTime() - date.getTime() < 6 * 86_400_000;
		return new Intl.DateTimeFormat(
			undefined,
			withinWeek
				? { weekday: 'short' }
				: {
						month: 'short',
						day: 'numeric',
						year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric'
					}
		).format(date);
	}

	// A guarded group has no client to hold a read position against -- opening it can never clear its count.
	// This says why in the reader's own words rather than leaving them to guess.
	function needsReviewHint(group: ConversationGroup): string {
		return group.chatSession?.match_status === 'needs_review'
			? 'This chat matched two different customers. Open it and choose which one to clear this.'
			: "This message isn't linked to a customer yet. Link it to a customer or dismiss it to clear this.";
	}

	const emptyTitle = $derived(
		lane !== 'all'
			? `No ${CHANNEL_LABELS[lane].toLowerCase()} conversations`
			: unreadOnly
				? 'No unread conversations'
				: emptyView === 'mine'
					? 'Nothing assigned to you yet'
					: 'No conversations yet'
	);
	const emptyDescription = $derived(
		lane !== 'all' || unreadOnly
			? 'Try All channels, or every conversation instead of unread only.'
			: emptyView === 'mine'
				? 'Conversations assigned to you or that you follow will appear here.'
				: 'Queued, sent, and received messages will appear here when they exist.'
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet row(group: ConversationGroup)}
	{@const channel = group.latest.channel as InboxChannel}
	{@const prefix = rowPrefix(group)}
	{@const selected = selectedKey === group.key}
	<div role="listitem">
		<button
			class="inbox-list__row"
			class:inbox-list__row--selected={selected}
			class:inbox-list__row--unread={group.unreadCount > 0}
			type="button"
			aria-current={selected ? 'true' : undefined}
			tabindex={rowTabStopKey === group.key ? 0 : -1}
			onfocus={() => (focusedRowKey = group.key)}
			onclick={() => onSelect(group)}
			onkeydown={handleRowKeydown}
		>
			{#if isUnknownCustomer(group)}
				<span class="inbox-list__unknown" aria-hidden="true">{@html userRoundIcon}</span>
			{:else}
				<Avatar id={group.avatarId} name={group.name} size="medium" />
			{/if}
			<span class="inbox-list__copy">
				<span class="inbox-list__line">
					<span class="inbox-list__name">
						<ChannelMark {channel} label={CHANNEL_LABELS[channel]} />
						<strong>{group.name}</strong>
					</span>
					<time datetime={group.latest.created_at}>{formatListTime(group.latest.created_at)}</time>
				</span>
				<span class="inbox-list__line inbox-list__line--preview">
					<span class="inbox-list__preview">{prefix ?? ''}{rowPreview(group)}</span>
					<span class="inbox-list__trail">
						{#if group.assignedToName}
							<span class="inbox-list__assigned" title={`Assigned to ${group.assignedToName}`}
								><span aria-hidden="true">{initials(group.assignedToName)}</span><span
									class="sr-only">Assigned to {group.assignedToName}</span
								></span
							>
						{/if}
						{#if group.guarded}
							{@const hint = needsReviewHint(group)}
							<span class="inbox-list__attention" title={hint}>
								<span class="inbox-list__attention-icon" aria-hidden="true"
									>{@html alertTriangleIcon}</span
								>
								{#if group.unreadCount > 0}<span aria-hidden="true">{group.unreadCount}</span>{/if}
								<span class="sr-only">{hint}</span>
							</span>
						{:else if group.unreadCount > 0}
							<span class="inbox-list__count">
								<span class="sr-only">{group.unreadCount} unread</span>
								<span aria-hidden="true">{group.unreadCount}</span>
							</span>
						{/if}
					</span>
				</span>
			</span>
		</button>
	</div>
{/snippet}

<aside class="inbox-list" aria-label="Conversations">
	<div class="inbox-list__header">
		<div class="inbox-list__top">
			<span class="inbox-list__tile" aria-hidden="true">{@html inboxIcon}</span>
			{#if canViewTeam}
				<SegmentedControl
					bind:value={view}
					size="small"
					ariaLabel="Inbox view"
					options={[
						{ value: 'team', label: 'Team' },
						{ value: 'mine', label: 'Mine' }
					]}
				/>
			{:else}
				<h2 class="inbox-list__title">My inbox</h2>
			{/if}
			<!-- Pick a client, then a channel they actually have -- Continue lands directly on that conversation. -->
			<Button size="small" class="inbox-list__new" onhover={onNewHover} onclick={onNew}>
				{@html pencilIcon}
				<span class="inbox-list__new-label">New</span>
			</Button>
		</div>
		<form
			class="inbox-list__search"
			role="search"
			onsubmit={(event) => {
				event.preventDefault();
				search = searchDraft;
			}}
		>
			<span class="inbox-list__search-icon" aria-hidden="true">{@html searchIcon}</span>
			<label class="sr-only" for="inbox-search">Search conversations</label>
			<input id="inbox-search" type="search" bind:value={searchDraft} placeholder="Search" />
			<span class="inbox-list__filter" class:inbox-list__filter--on={unreadOnly}>
				<DropdownMenu
					triggerLabel={unreadOnly ? 'Filter: unread only' : 'Filter conversations'}
					triggerIcon={filterIcon}
					triggerVariant="quiet"
					triggerSize="small"
					items={[
						{
							label: 'All conversations',
							current: !unreadOnly,
							onSelect: () => (unreadOnly = false)
						},
						{ label: 'Unread only', current: unreadOnly, onSelect: () => (unreadOnly = true) }
					]}
				/>
			</span>
		</form>
		<div class="inbox-list__lanes" role="group" aria-label="Channel">
			<button
				type="button"
				class="inbox-list__lane"
				class:inbox-list__lane--on={lane === 'all'}
				aria-pressed={lane === 'all'}
				onclick={() => (lane = 'all')}>All</button
			>
			{#each LANES as channel (channel)}
				<button
					type="button"
					class="inbox-list__lane"
					class:inbox-list__lane--on={lane === channel}
					aria-pressed={lane === channel}
					title={CHANNEL_LABELS[channel]}
					onclick={() => (lane = channel)}
				>
					<ChannelMark {channel} size={16} label={CHANNEL_LABELS[channel]} />
				</button>
			{/each}
		</div>
	</div>

	{#if orderedGroups.length === 0}
		<div class="inbox-list__empty">
			<EmptyState title={emptyTitle} description={emptyDescription} icon={inboxIcon} />
		</div>
	{:else}
		<div class="inbox-list__rows">
			{#if needsReply.length > 0}
				<h3 class="inbox-list__group">Needs reply · {needsReply.length}</h3>
				<div role="list" aria-label="Needs reply">
					{#each needsReply as group (group.key)}{@render row(group)}{/each}
				</div>
			{/if}
			{#if earlier.length > 0}
				<h3 class="inbox-list__group">{needsReply.length > 0 ? 'Earlier' : 'All conversations'}</h3>
				<div role="list" aria-label="Earlier">
					{#each earlier as group (group.key)}{@render row(group)}{/each}
				</div>
			{/if}
		</div>
	{/if}
</aside>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.inbox-list {
		display: flex;
		min-width: 0;
		min-height: 0;
		flex-direction: column;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__header {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: 18px var(--space-base) 10px;
		}

		&__top {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(.inbox-list__new) {
				margin-left: auto;
			}
		}

		&__tile {
			display: inline-grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
			border: var(--border-base) solid var(--color-conversation--surface-edge);
			border-radius: var(--radius-base);
			color: var(--color-conversation);
			background: var(--color-conversation--surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__search {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			height: 36px;
			padding: 0 2px 0 var(--space-base);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&:focus-within {
				border-color: var(--color-interactive);
				box-shadow: var(--shadow-focus);
			}

			input {
				min-width: 0;
				flex: 1;
				border: 0;
				outline: 0;
				color: var(--color-heading);
				background: transparent;
				font: inherit;
				font-size: var(--typography--fontSize-base);

				&::placeholder {
					color: var(--color-text--secondary);
				}
			}

			.inbox-list__filter {
				display: inline-flex;
			}

			// The filter is on: its icon turns brand green, so a narrowed list never looks like the whole inbox.
			.inbox-list__filter--on :global(.button) {
				color: var(--color-interactive);
			}
		}

		&__search-icon {
			display: inline-flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__lanes {
			display: flex;
			gap: 2px;
			padding: 3px;
			border: var(--border-base) solid var(--color-border);
			border-radius: 10px;
			background: var(--color-surface--hover);
		}

		&__lane {
			display: inline-flex;
			height: 30px;
			min-width: 0;
			flex: 1;
			align-items: center;
			justify-content: center;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;
			transition: background var(--timing-quick) ease-out;

			&:hover:not(.inbox-list__lane--on) {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: 0;
				box-shadow: var(--shadow-focus);
			}

			&--on {
				background: var(--color-surface);
				box-shadow: var(--shadow-button);
			}
		}

		&__rows {
			min-height: 0;
			flex: 1;
			overflow-y: auto;
			padding: 0 var(--space-small) var(--space-small);
		}

		&__group {
			margin: 0;
			padding: var(--space-base) var(--space-small) var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__row {
			display: flex;
			width: 100%;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px;
			border: 0;
			border-radius: 10px;
			color: inherit;
			background: transparent;
			font: inherit;
			text-align: left;
			cursor: pointer;
			transition: background var(--timing-quick) ease-out;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: 0;
				box-shadow: var(--shadow-focus);
			}

			&--selected,
			&--selected:hover {
				background: var(--color-surface--active);
			}
		}

		&__unknown {
			display: inline-grid;
			width: 40px;
			height: 40px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-circle);
			color: var(--color-inactive);
			background: var(--color-inactive--surface);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__copy {
			display: flex;
			min-width: 0;
			flex: 1;
			flex-direction: column;
			gap: 2px;
		}

		&__line {
			display: flex;
			min-width: 0;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);

			time {
				flex: 0 0 auto;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-overline);
				font-weight: 600;
			}
		}

		&__name {
			display: inline-flex;
			min-width: 0;
			align-items: center;
			gap: 6px;

			strong {
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}

		&__row--unread &__name strong {
			font-weight: 700;
		}

		&__row--unread &__line time {
			color: var(--color-interactive);
		}

		&__preview {
			display: -webkit-box;
			min-width: 0;
			overflow: hidden;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: 1.4;
			-webkit-box-orient: vertical;
			-webkit-line-clamp: 2;
			line-clamp: 2;
		}

		&__row:not(&__row--unread) &__preview {
			color: var(--color-text--secondary);
		}

		&__trail {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 6px;
		}

		&__assigned {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
		}

		&__count {
			display: inline-grid;
			min-width: 20px;
			height: 20px;
			place-items: center;
			padding: 0 6px;
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			background: var(--color-interactive);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
		}

		&__attention {
			display: inline-flex;
			align-items: center;
			gap: 2px;
			height: 20px;
			padding: 0 6px;
			border-radius: var(--radius-circle);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
		}

		&__attention-icon {
			display: inline-flex;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__empty {
			padding: var(--space-large);
		}
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}
</style>
