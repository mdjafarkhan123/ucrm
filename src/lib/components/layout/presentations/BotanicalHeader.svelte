<svelte:options css="injected" />

<script lang="ts">
	import type { HeaderFrameProps } from './header-types';
	let { identity, menu, search, add, appearance, notifications, accountControl }: HeaderFrameProps =
		$props();
</script>

<header class="botanical-header">
	{@render menu()}
	{@render identity?.()}
	{@render search()}
	<div class="botanical-header__actions">
		{@render appearance()}
		{@render notifications?.()}
		{@render add()}
		{@render accountControl()}
	</div>
</header>

<style lang="scss">
	.botanical-header {
		--botanical-header-ink: #243d34;
		--botanical-header-muted: #52604f;
		--botanical-header-surface: #fffefb;
		--botanical-header-border: #e2e6da;
		--botanical-header-action: #286b49;
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		flex: 0 0 auto;
		min-height: 88px;
		padding: 18px 20px;
		gap: 28px;
		background: var(--botanical-header-surface);
		border: 1px solid var(--botanical-header-border);
		border-radius: 12px;
		box-shadow: 0 3px 12px #34483304;
		color: var(--botanical-header-ink);
		font-family: Inter, 'Segoe UI', Arial, sans-serif;
		font-size: 0.9375rem;
		line-height: 1.6;
		&__actions {
			display: flex;
			align-items: center;
			gap: 6px;
			flex-shrink: 0;
		}
		:global(.topbar__search) {
			flex: 1;
			max-width: 440px;
			min-width: min(100%, 12rem);
			margin-inline: auto;
		}
		:global(.topbar__search-trigger),
		:global(.topbar__search-placeholder) {
			display: flex;
			align-items: center;
			gap: 10px;
			width: 100%;
			min-height: 44px;
			padding: 10px 14px;
			border: 1px solid #e0e5d8;
			border-radius: 12px;
			background: #f5f6ef;
			color: var(--botanical-header-muted);
			font: inherit;
			font-size: 0.875rem;
			text-align: left;
		}
		:global(.topbar__search-trigger) {
			cursor: pointer;
			&:hover {
				background: #edf2e5;
				border-color: #b9cbb0;
			}
		}
		:global(.topbar__search-label) {
			min-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		:global(.topbar__search-icon),
		:global(.topbar__search-icon svg) {
			display: inline-flex;
			flex-shrink: 0;
			width: 20px;
			height: 20px;
		}
		:global(.topbar__search-trigger kbd) {
			margin-left: auto;
			padding: 0 5px;
			border: 1px solid var(--botanical-header-border);
			border-radius: 4px;
			background: var(--botanical-header-surface);
			font-size: 0.6875rem;
			line-height: 1.6;
			white-space: nowrap;
		}
		:global(.topbar__icon-btn),
		:global(.notification-bell__trigger),
		:global(.topbar__menu) {
			display: inline-grid;
			place-items: center;
			width: 44px;
			height: 44px;
			padding: 0;
			flex-shrink: 0;
			border: 0;
			border-radius: 8px;
			background: transparent;
			color: var(--botanical-header-ink);
			cursor: pointer;
			&:hover {
				background: #e7eddf;
			}
		}
		:global(.topbar__menu) {
			display: none;
		}
		:global(.topbar__icon-btn span),
		:global(.topbar__icon-btn svg),
		:global(.topbar__menu span),
		:global(.topbar__menu svg) {
			display: inline-flex;
			width: 20px;
			height: 20px;
		}
		:global(.topbar__add) {
			display: inline-flex;
			justify-content: center;
			align-items: center;
			gap: 8px;
			flex-shrink: 0;
			min-height: 42px;
			padding: 9px 13px;
			margin-inline: 10px;
			border: 1px solid var(--botanical-header-action);
			border-radius: 10px;
			background: var(--botanical-header-action);
			color: white;
			font: inherit;
			font-size: 0.875rem;
			font-weight: 600;
			line-height: 1.6;
			white-space: nowrap;
			cursor: pointer;
			&:hover:not(:disabled) {
				background: #205b3e;
			}
		}
		:global(.topbar__add span:first-child),
		:global(.topbar__add svg) {
			display: inline-flex;
			width: 20px;
			height: 20px;
		}
		:global(.topbar__account) {
			display: grid;
			place-items: center;
			flex-shrink: 0;
			width: 40px;
			height: 40px;
			overflow: hidden;
			padding: 0;
			border: 1px solid #ded6c5;
			border-radius: 50%;
			background: #eee8dc;
			color: #67573e;
			font: inherit;
			font-size: 0.8125rem;
			font-weight: 600;
			cursor: pointer;
			&:hover {
				background: #e5ddce;
			}
		}
		:global(.topbar__avatar) {
			display: grid;
			place-items: center;
			width: 100%;
			height: 100%;
		}
		:global(.topbar__avatar .avatar) {
			--avatar-bg: #eee8dc;
			--avatar-fg: #67573e;
			width: 100%;
			height: 100%;
			font-size: 0.8125rem;
		}
		:global(.topbar__avatar svg) {
			width: 20px;
			height: 20px;
		}
		:global(button:focus-visible) {
			outline: 3px solid #619272;
			outline-offset: 3px;
		}
		:global(button:disabled) {
			cursor: not-allowed;
			opacity: 0.6;
		}
	}
	@media (min-width: 768px) and (max-width: 1100px) {
		.botanical-header {
			gap: 14px;
			padding-inline: 24px;
			:global(.topbar__search) {
				max-width: 280px;
			}
			:global(.topbar__search-trigger kbd) {
				display: none;
			}
		}
	}
	@media (max-width: 767px) {
		.botanical-header {
			padding: 12px 16px;
			gap: 6px;
			min-height: 126px;
			border-radius: 0;
			border: 0;
			border-bottom: 1px solid var(--botanical-header-border);
			&__actions {
				gap: 0;
			}
			:global(.topbar__menu) {
				display: inline-grid;
			}
			:global(.topbar__search) {
				order: 4;
				flex-basis: 100%;
				max-width: none;
				width: 100%;
				min-width: 0;
				margin: 4px 0 0;
			}
			:global(.topbar__search-trigger) {
				padding: 8px 12px;
				min-height: 42px;
				font-size: 0.8125rem;
			}
			:global(.topbar__search-trigger kbd),
			:global(.topbar__add-label) {
				display: none;
			}
			:global(.topbar__add) {
				margin-inline: 3px;
				width: 40px;
				min-height: 40px;
				padding: 0;
			}
			:global(.topbar__account) {
				width: 36px;
				height: 36px;
			}
		}
	}
</style>
