<script lang="ts">
	import arrowIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';

	type KpiTone =
		| 'default'
		| 'brand'
		| 'success'
		| 'warning'
		| 'informative'
		| 'critical'
		| 'inactive'
		| 'feature';
	type KpiVariant = 'standard' | 'compact';

	let {
		label,
		value,
		note,
		icon,
		tone = 'default',
		variant = 'standard',
		href,
		onclick,
		selected = false,
		alert = false,
		loading = false,
		disabled = false,
		secondaryValue,
		secondaryNote,
		change,
		rows = []
	}: {
		label: string;
		value: string;
		note: string;
		icon: string;
		tone?: KpiTone;
		variant?: KpiVariant;
		/** A resolved path to the list behind the number. */
		href?: string;
		/** Filters the existing list in place; links take precedence. */
		onclick?: () => void;
		selected?: boolean;
		alert?: boolean;
		loading?: boolean;
		disabled?: boolean;
		secondaryValue?: string;
		secondaryNote?: string;
		change?: { direction: 'up' | 'down' | 'same'; text: string } | null;
		rows?: { label: string; value: string; count?: string }[];
	} = $props();

	const tileTone = $derived(tone === 'default' ? 'inactive' : tone === 'brand' ? 'success' : tone);
	const classes = $derived([
		'kpi-card',
		`kpi-card--${tone}`,
		`kpi-card--${variant}`,
		(href || onclick) && 'kpi-card--interactive',
		selected && 'kpi-card--selected',
		alert && 'kpi-card--alert',
		value.length > 7 && 'kpi-card--long-value'
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet body()}
	<div class="kpi-card__topline">
		<IconTile {icon} tone={tileTone} size={48} white={alert} />
		<div class="kpi-card__figure">
			<strong>{loading ? '—' : value}</strong>
			<span>{label}</span>
		</div>
	</div>
	{#if href || onclick}<span class="kpi-card__arrow" aria-hidden="true">{@html arrowIcon}</span
		>{/if}
	<div class="kpi-card__note">
		{#if secondaryValue !== undefined}
			<strong class="kpi-card__secondary-value">{loading ? '—' : secondaryValue}</strong>
			<span>{secondaryNote}</span>
		{/if}
		{#if change && !loading}<span class="kpi-card__change">{change.text}</span>{/if}
		{#if note}<span>{loading ? 'Loading…' : note}</span>{/if}
		{#if rows.length > 0 && !loading}
			<dl class="kpi-card__rows">
				{#each rows as row (row.label)}
					<div>
						<dt>{row.label}</dt>
						<dd>{row.count ? `${row.count} · ` : ''}{row.value}</dd>
					</div>
				{/each}
			</dl>
		{/if}
	</div>
{/snippet}
{#if href}
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- caller supplies a resolved path. -->
	<a class={classes} {href} aria-busy={loading || undefined}>{@render body()}</a>
{:else if onclick}
	<button
		type="button"
		class={classes}
		{onclick}
		{disabled}
		aria-pressed={selected}
		aria-busy={loading || undefined}
	>
		{@render body()}
	</button>
{:else}
	<article class={classes} aria-busy={loading || undefined}>{@render body()}</article>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.kpi-card {
		--kpi-label: var(--color-inactive--onSurface);
		--kpi-figure: var(--color-heading);
		--kpi-note: var(--color-text--secondary);
		--kpi-band: var(--color-surface--background);
		container-type: inline-size;
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		min-width: 0;
		width: 100%;
		padding: var(--space-base) var(--space-slim) calc(var(--space-base) - var(--space-smallest));
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		color: var(--color-heading);
		font: inherit;
		text-align: left;
		text-decoration: none;

		@each $tone in success, warning, informative, critical {
			&--#{$tone} {
				--kpi-label: var(--color-#{$tone}--onSurface);
			}
		}
		&--brand {
			--kpi-label: var(--color-success--onSurface);
		}
		&--interactive {
			cursor: pointer;
		}
		&--interactive:hover {
			background: var(--color-surface--hover);
			border-color: var(--color-border--interactive--hover);
		}
		&--interactive:active {
			background: var(--color-surface--active);
		}
		&--interactive:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--interactive:disabled {
			cursor: default;
			opacity: 0.5;
		}
		&--alert {
			--kpi-figure: var(--color-critical--onSurface);
			--kpi-note: var(--color-critical--onSurface);
			--kpi-band: var(--color-surface);
			background: var(--color-critical--surface);
			border-color: var(--color-critical--surface-edge);
		}
		&--alert:hover {
			background: var(--color-critical--surface);
			border-color: var(--color-critical);
		}
		&--selected {
			box-shadow: inset 0 0 0 var(--border-thick) var(--color-interactive);
		}
		&--selected:focus-visible {
			box-shadow:
				inset 0 0 0 var(--border-thick) var(--color-interactive),
				var(--shadow-focus);
		}
		&__topline {
			display: flex;
			align-items: center;
			gap: calc(var(--space-small) + var(--space-smallest));
		}
		&__figure {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
			strong {
				color: var(--kpi-figure);
				font-size: calc(var(--typography--fontSize-display) + var(--space-smallest));
				font-variant-numeric: tabular-nums;
				line-height: 1;
				font-weight: 700;
				letter-spacing: -0.8px;
				overflow-wrap: anywhere;
			}
			span {
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
				line-height: 1.3;
				color: var(--kpi-label);
			}
		}
		&__arrow {
			position: absolute;
			top: var(--space-base);
			right: var(--space-slim);
			display: flex;
			color: var(--color-icon--secondary);
			:global(svg) {
				width: var(--space-base);
				height: var(--space-base);
			}
		}
		&--interactive &__figure {
			padding-right: var(--space-base);
		}
		&--alert &__arrow {
			color: var(--color-critical);
		}
		&__note {
			display: grid;
			gap: var(--space-smallest);
			margin-top: auto;
			padding: var(--space-small) calc(var(--space-small) + var(--space-smallest));
			border-radius: var(--radius-base);
			background: var(--kpi-band);
			color: var(--kpi-note);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: 1.4;
			overflow-wrap: anywhere;
		}
		&__secondary-value {
			color: var(--kpi-figure);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
		&__change {
			color: var(--kpi-figure);
			font-weight: 600;
		}
		&__rows {
			display: grid;
			gap: var(--space-small);
			margin: var(--space-small) 0 0;
			div {
				display: flex;
				flex-wrap: wrap;
				align-items: baseline;
				justify-content: space-between;
				gap: var(--space-smallest) var(--space-small);
			}
			dd {
				margin: 0;
				color: var(--kpi-figure);
				font-weight: 700;
			}
		}
		&--feature {
			--kpi-label: var(--color-feature--text--secondary);
			--kpi-figure: var(--color-feature--text);
			--kpi-note: var(--color-feature--text--secondary);
			--kpi-band: var(--color-feature--subtle);
			border-color: transparent;
			background:
				radial-gradient(
					ellipse at top right,
					var(--color-feature--glow),
					var(--color-feature--glow-end)
				),
				linear-gradient(110deg, var(--color-feature--start), var(--color-feature--end));
			color: var(--color-feature--text);
		}
		&--feature &__note {
			border: var(--border-base) solid var(--color-feature--border);
		}
	}
	@container (max-width: 180px) {
		.kpi-card--long-value .kpi-card__topline {
			flex-direction: column;
			align-items: flex-start;
		}
		.kpi-card--long-value .kpi-card__figure {
			padding-right: 0;
			strong {
				font-size: clamp(
					var(--typography--fontSize-base),
					13cqi,
					var(--typography--fontSize-largest)
				);
			}
		}
	}
</style>
