<script lang="ts" module>
	export type NotificationBellRecord =
		| 'request'
		| 'quote'
		| 'invoice'
		| 'conversation'
		| 'time'
		| 'review'
		| 'growth';

	export type NotificationBellItem = {
		id: string;
		title: string;
		body?: string | null;
		/** The short time shown in the timeline, for example "2h ago". */
		time: string;
		/** The exact time, shown on hover. */
		timeTitle?: string;
		unread: boolean;
		tone?: 'default' | 'attention' | 'urgent';
		/** The kind of record the alert is about: it picks the tile's colour. */
		record: NotificationBellRecord;
		/** The tile's Tabler icon (raw SVG). */
		icon: string;
	};
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import { Popover } from 'bits-ui';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import checksIcon from '@tabler/icons/outline/checks.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';

	// The header bell's look and interaction, shared by the Platform Owner bell and the contractor team bell.
	// Each caller owns its own query, read-marking and navigation; this only draws the trigger, the unread
	// badge and the popover panel (design skill `modals.md`, "Notification bell pop-up").

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
		onRetry,
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
		onRetry?: () => void;
		footer?: Snippet;
	} = $props();

	const unreadLabel = $derived(unreadCount > 99 ? '99+' : String(unreadCount));

	// An unread orange or red alert is pinned above the timeline until it is read.
	const toneOf = (item: NotificationBellItem) =>
		item.tone === 'urgent' ? 'critical' : item.tone === 'attention' ? 'warning' : null;
	const needsYou = $derived(items.filter((item) => item.unread && toneOf(item)));
	const latest = $derived(items.filter((item) => !(item.unread && toneOf(item))));
	const needsYouCount = $derived(needsYou.length);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Popover.Root bind:open>
	<Popover.Trigger>
		{#snippet child({ props })}
			<Button
				{...props}
				class="notification-bell__trigger"
				variant="secondary"
				size="large"
				iconOnly
				label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications, all read'}
			>
				{@html bellIcon}
				{#if unreadCount > 0}
					<span class="notification-bell__count" aria-hidden="true">{unreadLabel}</span>
				{/if}
			</Button>
		{/snippet}
	</Popover.Trigger>
	<Popover.Portal>
		<Popover.Content
			class="notification-bell__panel"
			align="end"
			sideOffset={12}
			collisionPadding={12}
		>
			<span class="notification-bell__arrow" aria-hidden="true"></span>
			<div class="notification-bell__surface">
				<header class="notification-bell__header">
					<div class="notification-bell__heading">
						<h2>Notifications</h2>
						{#if !loading && !loadError}
							<p class="notification-bell__summary">
								{#if unreadCount > 0}
									<span class="notification-bell__summary-part">
										<span class="notification-bell__summary-dot notification-bell__summary-dot--unread"
										></span>
										{unreadCount} unread
									</span>
									{#if needsYouCount > 0}
										<span class="notification-bell__summary-part">
											<span
												class="notification-bell__summary-dot notification-bell__summary-dot--critical"
											></span>
											{needsYouCount} need you
										</span>
									{/if}
								{:else}
									<span class="notification-bell__summary-part notification-bell__summary-part--clear">
										{@html circleCheckIcon}
										All caught up
									</span>
								{/if}
							</p>
						{/if}
					</div>
					{#if unreadCount > 0 && !loading && !loadError}
						<Button variant="secondary" size="small" onclick={onMarkAll} loading={markingAll}>
							<span class="notification-bell__mark-icon">{@html checksIcon}</span>
							Mark all read
						</Button>
					{/if}
					<Button
						variant="quiet"
						size="base"
						iconOnly
						label="Close notifications"
						onclick={() => (open = false)}
					>
						{@html closeIcon}
					</Button>
				</header>

				{#if actionError}
					<div class="notification-bell__notice">
						<Banner type="error">{actionError}</Banner>
					</div>
				{/if}

				<div class="notification-bell__list">
					{#if loading}
						<ul class="notification-bell__bones" aria-label="Loading notifications">
							{#each [0, 1, 2, 3] as bone (bone)}
								<li class="notification-bell__bone">
									<span class="skeleton notification-bell__bone-time"></span>
									<span class="skeleton notification-bell__bone-tile"></span>
									<span class="notification-bell__bone-lines">
										<span class="skeleton notification-bell__bone-line"></span>
										<span class="skeleton notification-bell__bone-line notification-bell__bone-line--short"
										></span>
									</span>
								</li>
							{/each}
						</ul>
					{:else if loadError}
						<div class="notification-bell__state">
							<IconTile icon={alertIcon} tone="critical" size={40} />
							<h3>Notifications couldn't load</h3>
							<p>{loadError}</p>
							{#if onRetry}
								<Button variant="secondary" size="small" onclick={onRetry}>
									{@html refreshIcon}
									Try again
								</Button>
							{/if}
						</div>
					{:else if items.length === 0}
						<div class="notification-bell__state">
							<IconTile icon={bellIcon} tone="inactive" size={40} />
							<h3>No notifications yet</h3>
							<p>{emptyText}</p>
						</div>
					{:else}
						{#if needsYou.length > 0}
							<section class="notification-bell__needs" aria-label="Needs you">
								<h3 class="notification-bell__label notification-bell__label--needs">
									{@html alertIcon}
									Needs you
								</h3>
								{#each needsYou as item (item.id)}
									<button
										class="notification-bell__card notification-bell__card--{toneOf(item)}"
										type="button"
										onclick={() => onOpenItem(item.id)}
									>
										<span class="notification-bell__card-tile">
											<IconTile icon={item.icon} tone={item.record} size={32} white />
										</span>
										<span class="notification-bell__card-text">
											<span class="notification-bell__card-title">{item.title}</span>
											{#if item.body}
												<span class="notification-bell__card-detail">{item.body}</span>
											{/if}
											<span class="notification-bell__card-time" title={item.timeTitle}>
												{item.time}
											</span>
										</span>
										<span class="notification-bell__card-chevron" aria-hidden="true">
											{@html chevronIcon}
										</span>
									</button>
								{/each}
							</section>
						{/if}

						{#if latest.length > 0}
							<section class="notification-bell__latest" aria-label="Latest">
								<h3 class="notification-bell__label">Latest</h3>
								<ul class="notification-bell__timeline">
									{#each latest as item (item.id)}
										<li>
											<button
												class="notification-bell__row"
												class:notification-bell__row--unread={item.unread}
												type="button"
												onclick={() => onOpenItem(item.id)}
											>
												<span
													class="notification-bell__time {toneOf(item)
														? `notification-bell__time--${toneOf(item)}`
														: ''}"
													title={item.timeTitle}>{item.time}</span
												>
												<span class="notification-bell__rail">
													<span class="notification-bell__tile">
														<IconTile icon={item.icon} tone={item.record} size={32} />
														{#if item.unread || toneOf(item)}
															<span
																class="notification-bell__dot {toneOf(item)
																	? `notification-bell__dot--${toneOf(item)}`
																	: ''}"
																aria-hidden="true"
															></span>
														{/if}
													</span>
													<span class="notification-bell__line"></span>
												</span>
												<span class="notification-bell__row-text">
													<span class="notification-bell__row-title">{item.title}</span>
													{#if item.body}
														<span class="notification-bell__row-detail">{item.body}</span>
													{/if}
												</span>
											</button>
										</li>
									{/each}
								</ul>
							</section>
						{/if}
					{/if}
				</div>

				{#if footer}
					<footer class="notification-bell__footer">{@render footer()}</footer>
				{/if}
			</div>
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
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

	// The panel is a see-through frame so the arrow can sit outside the clipped surface.
	:global(.notification-bell__panel) {
		z-index: var(--elevation-menu);
		display: flex;
		width: min(440px, calc(100vw - var(--space-large) * 2));
		max-height: min(640px, 80vh);
		flex-direction: column;
	}

	// A turned square with an edge on its two outer sides, so it reads against the page in light and dark.
	.notification-bell__arrow {
		position: absolute;
		top: -6px;
		// The bell is a 40 square at the panel's right edge, so its middle is 20 in.
		right: 14px;
		z-index: 1;
		width: 12px;
		height: 12px;
		border-top: var(--border-base) solid var(--color-border);
		border-left: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
		transform: rotate(45deg);
	}

	.notification-bell__surface {
		display: flex;
		min-height: 0;
		flex: 1;
		flex-direction: column;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: 0 12px 32px rgb(0 0 0 / 14%);
	}

	.notification-bell__header {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: 20px 16px 14px 20px;
	}

	.notification-bell__heading {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
		gap: 4px;

		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			letter-spacing: -0.3px;
			line-height: 1.2;
		}
	}

	.notification-bell__summary {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px 12px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.notification-bell__summary-part {
		display: inline-flex;
		align-items: center;
		gap: 6px;

		&--clear {
			color: var(--color-success--onSurface);
			font-weight: 500;

			:global(svg) {
				width: 14px;
				height: 14px;
				color: var(--color-success);
			}
		}
	}

	.notification-bell__summary-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;

		&--unread {
			background: var(--color-interactive);
		}

		&--critical {
			background: var(--color-critical);
		}
	}

	.notification-bell__mark-icon {
		display: inline-flex;
		color: var(--color-interactive);
	}

	.notification-bell__notice {
		padding: 0 16px 12px;
	}

	.notification-bell__list {
		min-height: 0;
		flex: 1;
		overflow-y: auto;
	}

	.notification-bell__label {
		display: flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		letter-spacing: 0.6px;
		text-transform: uppercase;

		&--needs {
			color: var(--color-text--secondary);

			:global(svg) {
				width: 14px;
				height: 14px;
				color: var(--color-critical);
			}
		}
	}

	// Needs you
	.notification-bell__needs {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 4px 16px 16px;
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.notification-bell__card {
		display: flex;
		width: 100%;
		align-items: center;
		gap: 12px;
		padding: 12px;
		border: var(--border-base) solid var(--card-edge);
		border-radius: 12px;
		background: var(--card-surface);
		color: var(--card-ink);
		text-align: left;
		cursor: pointer;

		&--critical {
			--card-surface: var(--color-critical--surface);
			--card-edge: var(--color-critical--surface-edge);
			--card-ink: var(--color-critical--onSurface);
		}

		&--warning {
			--card-surface: var(--color-warning--surface);
			--card-edge: var(--color-warning--surface-edge);
			--card-ink: var(--color-warning--onSurface);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notification-bell__card-tile {
		display: inline-flex;
		flex: 0 0 auto;

		// A white 36 tile (radius 9) on the tone colour.
		:global(.icon-tile) {
			width: 36px;
			height: 36px;
			border-radius: 9px;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}

	.notification-bell__card-text {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
		gap: 2px;
	}

	.notification-bell__card-title {
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	.notification-bell__card-detail {
		font-size: var(--typography--fontSize-small);
	}

	.notification-bell__card-time {
		font-size: var(--typography--fontSize-small);
		opacity: 0.8;
	}

	.notification-bell__card-chevron {
		display: inline-flex;
		flex: 0 0 auto;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	// Latest
	.notification-bell__latest {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 14px 16px 8px;
	}

	.notification-bell__timeline {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.notification-bell__row {
		display: flex;
		width: 100%;
		align-items: stretch;
		gap: 12px;
		padding: 0 8px 0 4px;
		border: 0;
		border-radius: 10px;
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
	}

	.notification-bell__time {
		width: 60px;
		flex: 0 0 auto;
		padding-top: 8px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: right;

		.notification-bell__row--unread & {
			color: var(--color-heading);
			font-weight: 600;
		}

		&--warning {
			color: var(--color-warning--onSurface);
			font-weight: 600;
		}

		&--critical {
			color: var(--color-critical);
			font-weight: 600;
		}
	}

	.notification-bell__rail {
		display: flex;
		width: 32px;
		flex: 0 0 auto;
		flex-direction: column;
		align-items: center;
		gap: 4px;
	}

	.notification-bell__tile {
		position: relative;
		display: inline-flex;
		margin-top: 4px;
	}

	.notification-bell__dot {
		position: absolute;
		top: -3px;
		right: -3px;
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--color-interactive);
		box-shadow: 0 0 0 2px var(--color-surface);

		&--warning {
			background: var(--color-warning);
		}

		&--critical {
			background: var(--color-critical);
		}
	}

	.notification-bell__line {
		width: 2px;
		flex: 1;
		min-height: 8px;
		border-radius: 1px;
		background: var(--color-border);

		li:last-child & {
			visibility: hidden;
		}
	}

	.notification-bell__row-text {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
		gap: 2px;
		padding: 8px 0 16px;
	}

	.notification-bell__row-title {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;

		.notification-bell__row--unread & {
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.notification-bell__row-detail {
		display: -webkit-box;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}

	// Loading
	.notification-bell__bones {
		display: flex;
		flex-direction: column;
		gap: 22px;
		margin: 0;
		padding: 20px 16px 20px 20px;
		list-style: none;
	}

	.notification-bell__bone {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.notification-bell__bone-time {
		width: 36px;
		height: 8px;
		margin: 0 12px 0 12px;
	}

	.notification-bell__bone-tile {
		width: 32px;
		height: 32px;
		flex: 0 0 auto;
		border-radius: 8px;
	}

	.notification-bell__bone-lines {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 8px;
	}

	.notification-bell__bone-line {
		width: 85%;
		height: 10px;
		min-height: 0;

		&--short {
			width: 55%;
			height: 8px;
		}
	}

	// Empty and couldn't load
	.notification-bell__state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 12px;
		padding: 32px 40px 40px;
		text-align: center;

		h3 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		p {
			max-width: 320px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}
	}

	.notification-bell__footer {
		padding: 12px 16px 16px;
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
</style>
