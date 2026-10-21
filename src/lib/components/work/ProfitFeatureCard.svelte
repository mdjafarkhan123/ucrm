<script lang="ts" module>
	export type ProfitPart = {
		key: string;
		label: string;
		/** Already formatted, e.g. "$5,320". */
		amount: string;
		/** This part's share of the bar, 0–1. A part with no share has no segment but keeps its legend row. */
		share: number;
		/** Whole-number percent shown before the amount, or null to leave it out. */
		percent: number | null;
		/** `none` draws a plain legend row with no swatch, e.g. a count. */
		tone: 'violet' | 'blue' | 'amber' | 'green' | 'muted' | 'none';
	};
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import trendIcon from '@tabler/icons/outline/trending-up.svg?raw';

	// The dark featured card on Classic record pages (classic.pen "Profit card", and the invoice's "Balance
	// card"): one headline figure, an optional pill, a split bar and its legend. It only draws what it is
	// handed; the job, quote and invoice cards work out their own figures and wording.
	let {
		label,
		eyebrow,
		value,
		loss = false,
		margin = null,
		subline,
		parts,
		showBar = true,
		chip,
		pillIcon = trendIcon,
		compact = false,
		children
	}: {
		/** Names the card out loud, e.g. "Job profit". */
		label: string;
		eyebrow: string;
		value: string;
		loss?: boolean;
		margin?: string | null;
		subline: string;
		parts: ProfitPart[];
		showBar?: boolean;
		/** The small chip beside the eyebrow. Defaults to the profit card's "Team only" lock. */
		chip?: { label: string; icon: string };
		/** The icon inside the margin pill. */
		pillIcon?: string;
		/** A name rather than a figure in the headline (the request's follow-up card): a smaller size. */
		compact?: boolean;
		/** Notes under the legend. */
		children?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="profit-card" aria-label={label}>
	<header class="profit-card__header">
		<p class="profit-card__eyebrow">{eyebrow}</p>
		<span class="profit-card__team">
			<span aria-hidden="true">{@html chip?.icon ?? lockIcon}</span>{chip?.label ?? 'Team only'}
		</span>
	</header>

	<div class="profit-card__figure">
		<div class="profit-card__figure-row">
			<p
				class="profit-card__value"
				class:profit-card__value--loss={loss}
				class:profit-card__value--compact={compact}
			>
				{value}
			</p>
			{#if margin}
				<span class="profit-card__margin">
					<span aria-hidden="true">{@html pillIcon}</span>{margin}
				</span>
			{/if}
		</div>
		<p class="profit-card__sub">{subline}</p>
	</div>

	{#if showBar && parts.length > 0}
		<div class="profit-card__bar" aria-hidden="true">
			{#each parts as part (part.key)}
				{#if part.share > 0}
					<span
						class={`profit-card__segment profit-card__segment--${part.tone}`}
						style:flex-grow={part.share}
					></span>
				{/if}
			{/each}
		</div>
	{/if}

	{#if parts.length > 0}
		<dl class="profit-card__legend">
			{#each parts as part (part.key)}
				<div class="profit-card__row">
					<dt>
						{#if part.tone !== 'none'}<span
								class={`profit-card__swatch profit-card__segment--${part.tone}`}
							></span>{/if}{part.label}
					</dt>
					<dd>
						{#if part.percent !== null}<span>{part.percent}%</span>{/if}
						<strong>{part.amount}</strong>
					</dd>
				</div>
			{/each}
		</dl>
	{/if}

	{#if children}{@render children()}{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.profit-card {
		display: flex;
		flex-direction: column;
		gap: 20px;
		padding: 24px;
		border-radius: var(--classic2-radius-card);
		background: linear-gradient(
			120deg,
			var(--classic2-sidebar) 0%,
			var(--classic2-feature-mid) 60%,
			var(--classic2-feature-end) 100%
		);
		box-shadow: 0 10px 28px var(--classic2-shadow-feature);
		color: var(--classic2-white);
		font-family: var(--classic2-font);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
		}

		&__eyebrow {
			margin: 0;
			color: var(--classic2-feature-eyebrow);
			font-size: var(--classic2-font-micro);
			font-weight: 700;
			letter-spacing: 1px;
			text-transform: uppercase;
		}

		&__team {
			display: inline-flex;
			align-items: center;
			gap: 5px;
			padding: 4px 9px;
			border-radius: 999px;
			background: var(--classic2-feature-chip);
			color: var(--classic2-feature-label);
			font-size: var(--classic2-font-small);
			font-weight: 600;

			span {
				display: inline-flex;
				color: var(--classic2-feature-eyebrow);
			}

			:global(svg) {
				width: 11px;
				height: 11px;
			}
		}

		&__figure {
			display: flex;
			flex-direction: column;
			gap: 6px;
		}

		&__figure-row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: 10px;
		}

		&__value {
			margin: 0;
			color: var(--classic2-white);
			font-size: 40px;
			font-weight: 700;
			letter-spacing: -1.2px;
			line-height: 1;

			&--loss {
				color: var(--classic2-savebar-error);
			}

			&--compact {
				font-size: 24px;
				letter-spacing: -0.6px;
				line-height: 1.2;
			}
		}

		&__margin {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			padding: 4px 9px;
			border-radius: 999px;
			background: var(--classic2-solid-green);
			color: var(--classic2-green-on);
			font-size: var(--classic2-font-label);
			font-weight: 700;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__sub {
			margin: 0;
			color: var(--classic2-feature-eyebrow);
			font-size: var(--classic2-font-label);
			font-weight: 500;
		}

		&__bar {
			display: flex;
			gap: 3px;
			height: 10px;
		}

		&__segment {
			flex-basis: 0;
			border-radius: 4px;

			&--violet {
				background: var(--classic2-violet-dot);
			}

			&--blue {
				background: var(--classic2-blue-dot);
			}

			&--amber {
				background: var(--classic2-amber-dot);
			}

			&--green {
				background: var(--classic2-green-mid);
			}

			&--muted {
				background: var(--classic2-feature-muted);
			}
		}

		&__legend {
			display: flex;
			flex-direction: column;
			gap: 10px;
			margin: 0;
		}

		&__row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
			font-size: var(--classic2-font-label);

			dt {
				display: inline-flex;
				align-items: center;
				gap: 8px;
				color: var(--classic2-feature-label);
				font-weight: 500;
			}

			dd {
				display: inline-flex;
				gap: 8px;
				margin: 0;

				span {
					color: var(--classic2-feature-muted);
					font-weight: 500;
				}

				strong {
					color: var(--classic2-white);
					font-weight: 600;
				}
			}
		}

		&__swatch {
			width: 8px;
			height: 8px;
			border-radius: 2px;
		}

		:global(.profit-card__note) {
			margin: 0;
			color: var(--classic2-feature-muted);
			font-size: var(--classic2-font-small);
			line-height: 1.45;

			&:global(.profit-card__note--warn) {
				color: var(--classic2-amber-dot);
			}
		}
	}
</style>
