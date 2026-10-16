<script lang="ts">
	// One row inside a flush rail card — a small icon tile, a quiet label over a value, and a text action at
	// the end ("Add", "Edit"). The discount and the tax of a priced record sit together in one such card,
	// each row owning only its own wording; the dialogs that change them stay with the discount and tax parts.
	let {
		icon,
		label,
		value,
		muted = false,
		actionLabel,
		actionName,
		onaction,
		onhover
	}: {
		/** A Tabler icon (raw SVG). */
		icon: string;
		label: string;
		value: string;
		/** Greys the value, for "No discount". */
		muted?: boolean;
		/** The word at the row's end. Leave out where the reader may not change it. */
		actionLabel?: string;
		/** What the action does out loud, e.g. "Edit the discount". */
		actionName?: string;
		onaction?: () => void;
		onhover?: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="adjustment-row">
	<span class="adjustment-row__tile" aria-hidden="true">{@html icon}</span>
	<div class="adjustment-row__text">
		<span class="adjustment-row__label">{label}</span>
		<span class={['adjustment-row__value', muted && 'adjustment-row__value--muted']}>{value}</span>
	</div>
	{#if actionLabel && onaction}
		<button
			type="button"
			class="adjustment-row__action"
			aria-label={actionName ?? actionLabel}
			onclick={onaction}
			onmouseenter={onhover}
			onfocus={onhover}
		>
			{actionLabel}
		</button>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.adjustment-row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 20px;
		border-top: var(--border-base) solid var(--color-border);

		&__tile {
			display: inline-grid;
			flex: 0 0 auto;
			width: 32px;
			height: 32px;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface--background--subtle);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__text {
			display: grid;
			flex: 1 1 auto;
			min-width: 0;
			gap: 2px;
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__value {
			overflow: hidden;
			color: var(--color-heading);
			font-size: 13px;
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;

			&--muted {
				color: var(--color-text--secondary);
			}
		}

		&__action {
			flex: 0 0 auto;
			padding: 4px 2px;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-size: 13px;
			font-weight: 600;
			cursor: pointer;

			&:hover {
				color: var(--color-interactive--hover);
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
