<script lang="ts">
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';

	// One destination inside a Settings group: an icon, a name, a one-line description, and an honest
	// status. The whole card is the link — Jobber and this app both treat the card as the affordance, not
	// a separate button inside it.
	let {
		href,
		icon,
		title,
		description,
		status,
		unavailable = false
	}: {
		href?: string;
		icon: string;
		title: string;
		description: string;
		status?: {
			label: string;
			tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
		};
		unavailable?: boolean;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if unavailable}
	<div class="settings-card settings-card--unavailable" aria-disabled="true">
		<span class="settings-card__icon" aria-hidden="true">{@html icon}</span>
		<span class="settings-card__body">
			<span class="settings-card__title">{title}</span>
			<span class="settings-card__description">{description}</span>
			{#if status}<StatusBadge status={status.tone}>{status.label}</StatusBadge>{/if}
		</span>
	</div>
{:else}
	<a class="settings-card" {href}>
		<span class="settings-card__icon" aria-hidden="true">{@html icon}</span>
		<span class="settings-card__body">
			<span class="settings-card__title">{title}</span>
			<span class="settings-card__description">{description}</span>
			{#if status}<StatusBadge status={status.tone}>{status.label}</StatusBadge>{/if}
		</span>
		<span class="settings-card__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
	</a>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.settings-card {
		display: flex;
		align-items: flex-start;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		text-decoration: none;
		transition: background-color var(--timing-quick);

		&--unavailable {
			cursor: default;
		}
		&:not(.settings-card--unavailable):hover,
		&:not(.settings-card--unavailable):focus-visible {
			background: var(--color-surface--hover);
		}
		&:not(.settings-card--unavailable):focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&__icon {
			display: grid;
			width: var(--space-larger);
			height: var(--space-larger);
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-interactive--subtle);
			background: var(--color-interactive--background--subtle--hover);
		}
		&__icon :global(svg) {
			width: 20px;
			height: 20px;
		}

		&__body {
			display: flex;
			min-width: 0;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__title {
			color: var(--color-heading);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__description {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__chevron {
			display: grid;
			width: 16px;
			height: 16px;
			flex: 0 0 auto;
			place-items: center;
			margin-top: var(--space-smaller);
			color: var(--color-icon--secondary);
		}
		&__chevron :global(svg) {
			width: 16px;
			height: 16px;
		}
	}
</style>
