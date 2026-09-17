<script lang="ts" module>
	export type NotificationBellItem = {
		id: string;
		title: string;
		body?: string | null;
		meta: string;
		metaTitle?: string;
		unread: boolean;
		tone?: 'default' | 'attention' | 'urgent';
	};
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import { Popover } from 'bits-ui';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';

	// The header bell's look and interaction, shared by the Platform Owner bell and the contractor team bell.
	// Each caller owns its own query, read-marking and navigation; this only draws the trigger, the unread
	// badge and the popover list.

	let {
		open = $bindable(false),
		items,
		unreadCount,
		loading,
		loadError = '',
		actionError = '',
		emptyText,
		markingAll = false,
		onMarkAll,
		onOpenItem,
		footer
	}: {
		open?: boolean;
		items: NotificationBellItem[];
		unreadCount: number;
		loading: boolean;
		loadError?: string;
		actionError?: string;
		emptyText: string;
		markingAll?: boolean;
		onMarkAll: () => void;
		onOpenItem: (id: string) => void;
		footer?: Snippet;
	} = $props();

	const unreadLabel = $derived(unreadCount > 99 ? '99+' : String(unreadCount));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Popover.Root bind:open>
	<Popover.Trigger
		class="notification-bell__trigger"
		aria-label={unreadCount > 0
			? `Notifications, ${unreadCount} unread`
			: 'Notifications, all read'}
	>
		<span class="notification-bell__icon" aria-hidden="true">{@html bellIcon}</span>
		{#if unreadCount > 0}
			<span class="notification-bell__count" aria-hidden="true">{unreadLabel}</span>
		{/if}
	</Popover.Trigger>
	<Popover.Portal>
		<Popover.Content
			class="notification-bell__panel"
			align="end"
			sideOffset={8}
			collisionPadding={12}
		>
			<header class="notification-bell__header">
				<h2>Notifications</h2>
				{#if unreadCount > 0}
					<button
						class="notification-bell__mark-all"
						type="button"
						onclick={onMarkAll}
						disabled={markingAll}
					>
						{markingAll ? 'Marking…' : 'Mark all read'}
					</button>
				{/if}
			</header>

			{#if actionError}
				<p class="notification-bell__error" role="alert">{actionError}</p>
			{/if}

			<div class="notification-bell__list">
				{#if loading}
					<p class="notification-bell__muted">Loading…</p>
				{:else if loadError}
					<p class="notification-bell__error" role="alert">{loadError}</p>
				{:else if items.length === 0}
					<p class="notification-bell__muted">{emptyText}</p>
				{:else}
					{#each items as item (item.id)}
						<button
							class="notification-bell__item"
							class:notification-bell__item--unread={item.unread}
							type="button"
							onclick={() => onOpenItem(item.id)}
						>
							<span
								class="notification-bell__dot"
								class:notification-bell__dot--unread={item.unread &&
									(item.tone ?? 'default') === 'default'}
								class:notification-bell__dot--attention={item.tone === 'attention'}
								class:notification-bell__dot--urgent={item.tone === 'urgent'}
								aria-hidden="true"
							></span>
							<span class="notification-bell__item-text">
								<span class="notification-bell__item-title">{item.title}</span>
								{#if item.body}
									<span class="notification-bell__item-body">{item.body}</span>
								{/if}
								<span class="notification-bell__item-meta" title={item.metaTitle}>{item.meta}</span>
							</span>
						</button>
					{/each}
				{/if}
			</div>

			{#if footer}
				<footer class="notification-bell__footer">{@render footer()}</footer>
			{/if}
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.notification-bell__trigger) {
		position: relative;
		display: inline-grid;
		width: 40px;
		height: 40px;
		place-items: center;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: var(--color-surface);
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notification-bell__icon,
	.notification-bell__icon :global(svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}

	.notification-bell__count {
		position: absolute;
		top: -6px;
		right: -6px;
		min-width: 18px;
		padding: 0 var(--space-smallest);
		border-radius: var(--radius-large);
		background: var(--color-critical);
		color: var(--color-text--reverse);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 18px;
		text-align: center;
	}

	:global(.notification-bell__panel) {
		z-index: var(--elevation-menu);
		display: flex;
		width: min(380px, calc(100vw - var(--space-large) * 2));
		max-height: min(70vh, 520px);
		flex-direction: column;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
	}

	.notification-bell__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);

		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
	}

	.notification-bell__mark-all {
		border: 0;
		background: transparent;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		cursor: pointer;

		&:hover:not(:disabled) {
			text-decoration: underline;
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notification-bell__list {
		flex: 1;
		overflow-y: auto;
	}

	.notification-bell__item {
		display: flex;
		width: 100%;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border: 0;
		border-bottom: var(--border-base) solid var(--color-border);
		background: transparent;
		text-align: left;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&--unread {
			background: var(--color-surface--background--subtle);
		}
	}

	.notification-bell__dot {
		width: 8px;
		height: 8px;
		flex: 0 0 auto;
		margin-top: 6px;
		border-radius: 50%;
		background: var(--color-border--interactive);

		&--unread {
			background: var(--color-interactive);
		}

		&--attention {
			background: var(--color-warning);
		}

		&--urgent {
			background: var(--color-critical);
		}
	}

	.notification-bell__item-text {
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.notification-bell__item-title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
	}

	.notification-bell__item--unread .notification-bell__item-title {
		font-weight: 600;
	}

	.notification-bell__item-body {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow: hidden;
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}

	.notification-bell__item-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}

	.notification-bell__footer {
		padding: var(--space-small) var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
		text-align: center;

		// The link arrives in the caller's snippet, so it carries the caller's scope, not this component's.
		:global(a) {
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
		}
	}

	.notification-bell__muted,
	.notification-bell__error {
		padding: var(--space-base);
		font-size: var(--typography--fontSize-small);
	}

	.notification-bell__muted {
		color: var(--color-text--secondary);
	}

	.notification-bell__error {
		color: var(--color-critical);
	}
</style>
