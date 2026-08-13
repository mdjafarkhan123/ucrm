<script lang="ts">
	type KpiTone = 'default' | 'brand' | 'success' | 'warning' | 'informative' | 'critical';
	type KpiVariant = 'standard' | 'compact';

	let {
		label,
		value,
		note,
		icon,
		tone = 'default',
		variant = 'standard'
	}: {
		label: string;
		value: string;
		note: string;
		icon: string;
		tone?: KpiTone;
		variant?: KpiVariant;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<article class={`kpi-card kpi-card--${tone} kpi-card--${variant}`}>
	<div class="kpi-card__topline">
		<span>{label}</span>
		<span class="kpi-card__icon" aria-hidden="true">{@html icon}</span>
	</div>
	<strong>{value}</strong>
	<small>{note}</small>
</article>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.kpi-card {
		min-height: 132px;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.kpi-card--brand {
		border-color: transparent;
		color: var(--color-text--reverse);
		background: var(--color-brand);
	}

	.kpi-card--compact {
		min-height: 0;
		padding: var(--space-base);

		.kpi-card__topline {
			align-items: center;
			font-size: var(--typography--fontSize-small);
		}

		.kpi-card__icon {
			width: 40px;
			height: 40px;
			flex-basis: 40px;
			border-radius: var(--radius-base);
			background: transparent;
		}

		.kpi-card__icon :global(svg) {
			width: 24px;
			height: 24px;
		}

		&.kpi-card--brand .kpi-card__icon {
			color: var(--color-text--reverse);
		}

		&.kpi-card--success .kpi-card__icon {
			color: var(--color-success);
		}

		&.kpi-card--warning .kpi-card__icon {
			color: var(--color-warning);
		}

		&.kpi-card--informative .kpi-card__icon {
			color: var(--color-informative);
		}

		&.kpi-card--critical .kpi-card__icon {
			color: var(--color-critical);
		}

		> strong {
			margin: var(--space-small) 0 var(--space-smaller);
			font-size: 28px;
		}

		> small {
			font-size: var(--typography--fontSize-small);
		}
	}

	.kpi-card__topline {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	.kpi-card--brand .kpi-card__topline,
	.kpi-card--brand small {
		color: var(--color-text--reverse);
		opacity: 0.82;
	}

	.kpi-card__icon {
		display: inline-flex;
		width: 48px;
		height: 48px;
		flex: 0 0 48px;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-base);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
	}

	.kpi-card__icon :global(svg) {
		width: 32px;
		height: 32px;
	}

	.kpi-card--success .kpi-card__icon {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}

	.kpi-card--warning .kpi-card__icon {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}

	.kpi-card--informative .kpi-card__icon {
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}

	.kpi-card--critical .kpi-card__icon {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}

	.kpi-card--brand .kpi-card__icon {
		color: var(--color-brand);
		background: var(--color-surface);
	}

	.kpi-card > strong {
		display: block;
		margin: var(--space-base) 0 var(--space-small);
		color: var(--color-heading);
		font-size: 36px;
		line-height: 1;
	}

	.kpi-card--brand > strong {
		color: var(--color-text--reverse);
	}

	.kpi-card > small {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
	}

	@media (max-width: 639px) {
		.kpi-card {
			min-height: 116px;
			padding: var(--space-base);
		}

		.kpi-card > strong {
			font-size: 30px;
		}
	}
</style>
