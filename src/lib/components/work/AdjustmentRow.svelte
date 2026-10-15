<script lang="ts">
	import type { Snippet } from 'svelte';

	// One line of the "Discount and tax" card: what it is, what it is set to, and the one verb that changes
	// it. The card around it comes from `RecordAdjustmentsCard`; the dialogs behind the verb stay with the
	// discount and tax cards that own them.
	let {
		icon,
		label,
		value,
		note = '',
		muted = false,
		action
	}: {
		/** A raw Tabler SVG. */
		icon: string;
		label: string;
		value: string;
		/** Small print under the value, e.g. where a tax rate came from. */
		note?: string;
		/** The value is an absence ("No discount") rather than a setting. */
		muted?: boolean;
		action?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="adjustment-row">
	<span class="adjustment-row__tile" aria-hidden="true">{@html icon}</span>
	<div class="adjustment-row__text">
		<span class="adjustment-row__label">{label}</span>
		<span class="adjustment-row__value" class:adjustment-row__value--muted={muted}>{value}</span>
		{#if note}<span class="adjustment-row__note">{note}</span>{/if}
	</div>
	{#if action}<div class="adjustment-row__action">{@render action()}</div>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.adjustment-row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 20px;
		border-top: 1px solid var(--classic2-divider);

		&__tile {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 32px;
			height: 32px;
			border-radius: 9px;
			color: var(--classic2-body);
			background: var(--classic2-chip);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__text {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__label {
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		&__value {
			color: var(--classic2-ink);
			font-size: var(--classic2-font-label);
			font-weight: 600;
			overflow-wrap: anywhere;

			&--muted {
				color: var(--classic2-secondary);
			}
		}

		&__note {
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		&__action {
			flex: 0 0 auto;
		}
	}

	// The verb reads as plain green text, as in the approved frame; a soft chip appears only on hover.
	:global(:root:has(.app-shell[data-presentation='classic']))
		.adjustment-row__action
		:global(.button.button--tertiary) {
		min-height: 28px;
		padding: 0 8px;
		color: var(--classic2-green);
		background: transparent;
		font-size: var(--classic2-font-label);
		font-weight: 600;
	}
	:global(:root:has(.app-shell[data-presentation='classic']))
		.adjustment-row__action
		:global(.button.button--tertiary:hover:not(:disabled)),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.adjustment-row__action
		:global(.button.button--tertiary:focus-visible:not(:disabled)) {
		color: var(--classic2-green-hover);
		background: var(--classic2-surface-soft);
	}
</style>
