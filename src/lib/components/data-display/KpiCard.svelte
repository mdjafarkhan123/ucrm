<script lang="ts">
	import arrowIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	type KpiTone = 'default' | 'brand' | 'success' | 'warning' | 'informative' | 'critical';
	type KpiVariant = 'standard' | 'compact';

	let {
		label,
		value,
		note,
		icon,
		tone = 'default',
		variant = 'standard',
		href,
		secondaryValue,
		secondaryNote
	}: {
		label: string;
		value: string;
		note: string;
		icon: string;
		tone?: KpiTone;
		variant?: KpiVariant;
		/** Makes the whole card a link to the list behind the number. Pass a resolved path. */
		href?: string;
		/** A second figure under the first, for a card that answers two questions (for example collected and left to collect). */
		secondaryValue?: string;
		secondaryNote?: string;
	} = $props();

	// The tile's colour family: the brand card uses the success green, a plain card the quiet grey.
	const tileTone = $derived(tone === 'default' ? 'inactive' : tone === 'brand' ? 'success' : tone);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet body()}
	<div class="kpi-card__topline">
		<IconTile {icon} tone={tileTone} />
		<div class="kpi-card__figure"><strong>{value}</strong><span>{label}</span></div>
		{#if href}<span class="kpi-card__arrow" aria-hidden="true">{@html arrowIcon}</span>{/if}
	</div>
	<small class="kpi-card__note">{note}</small>
	{#if secondaryValue !== undefined}<div class="kpi-card__secondary">
			<strong>{secondaryValue}</strong><small>{secondaryNote}</small>
		</div>{/if}
{/snippet}
{#if href}
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the caller passes a resolved path. -->
	<a class={`kpi-card kpi-card--${tone} kpi-card--${variant} kpi-card--link`} {href}>
		{@render body()}
	</a>
{:else}
	<article class={`kpi-card kpi-card--${tone} kpi-card--${variant}`}>
		{@render body()}
	</article>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.kpi-card {
		--kpi-text: var(--color-inactive--onSurface);
		display: flex;
		flex-direction: column;
		gap: 12px;
		min-width: 0;
		padding: 16px 16px 14px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		color: var(--color-heading);
		text-decoration: none;
		@each $tone in success, warning, informative, critical {
			&--#{$tone} {
				--kpi-text: var(--color-#{$tone}--onSurface);
			}
		}
		&--brand {
			--kpi-text: var(--color-success--onSurface);
		}
		&--link:hover {
			background: var(--color-surface--hover);
			border-color: var(--color-border--interactive--hover);
		}
		&--link:active {
			background: var(--color-surface--active);
		}
		&--link:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&__topline {
			display: flex;
			align-items: center;
			gap: 12px;
		}
		&__figure {
			display: flex;
			flex-direction: column;
			gap: 4px;
			min-width: 0;
			strong {
				font-size: 26px;
				line-height: 1.1;
				font-weight: 700;
				letter-spacing: -0.6px;
				overflow-wrap: anywhere;
			}
			span {
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
				color: var(--kpi-text);
			}
		}
		&__arrow {
			display: flex;
			margin-left: auto;
			color: var(--color-icon--secondary);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__note {
			display: block;
			margin-top: auto;
			padding: 8px 10px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__secondary {
			padding-top: 8px;
			border-top: 1px solid var(--color-border);
			strong,
			small {
				display: block;
			}
			strong {
				font-size: 20px;
			}
			small {
				font-size: var(--typography--fontSize-small);
				color: var(--color-text--secondary);
			}
		}
	}
</style>
