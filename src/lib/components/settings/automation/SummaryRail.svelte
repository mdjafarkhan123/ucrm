<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import type { AuthoredDefinition } from '$lib/automation/authoring';
	import { getCatalogEntry, triggerLabel } from '$lib/automation/catalog';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';

	// The builder's read-only rail: a plain-English retelling of the draft the user is editing, so they can
	// see the whole automation as a sentence while they work on one card. Presentational only — it derives
	// everything from the live definition and never writes.
	let {
		name,
		definition
	}: {
		name: string;
		definition: AuthoredDefinition;
	} = $props();

	const trimmedName = $derived(name.trim());

	function conditionLabel(key: string): string {
		return getCatalogEntry(key)?.label ?? key;
	}

	function stepLine(step: AuthoredDefinition['steps'][number]): string {
		if (step.key === 'wait.relative_delay') {
			const amount = Number(step.config?.amount);
			const unit = String(step.config?.unit ?? 'days');
			if (Number.isFinite(amount) && amount > 0) {
				const singular = unit.replace(/s$/, '');
				return `Wait ${amount} ${amount === 1 ? singular : `${singular}s`}`;
			}
			return 'Wait a while';
		}
		return getCatalogEntry(step.key)?.label ?? step.key;
	}

	// Every email the recipe could send in one run — the honest upper bound the contract asks the rail to
	// show, since waits and stops only ever reduce it.
	const maxMessages = $derived(
		definition.steps.filter((step) => step.key === 'action.send_email').length
	);
	const stepLines = $derived(definition.steps.map(stepLine));
</script>

<SectionBlock title="Summary" icon={listCheckIcon} level={2}>
	<div class="summary">
		<h3 class="summary__name">{trimmedName || 'Untitled automation'}</h3>

		<dl class="summary__list">
			<div class="summary__row">
				<dt>When</dt>
				<dd>{triggerLabel(definition.trigger?.key ?? null)}</dd>
			</div>

			<div class="summary__row">
				<dt>Only if</dt>
				<dd>
					{#if definition.conditions.length === 0}
						<span class="summary__muted">No extra conditions</span>
					{:else}
						<ul class="summary__inline-list">
							{#each definition.conditions as condition (condition.key)}
								<li>{conditionLabel(condition.key)}</li>
							{/each}
						</ul>
					{/if}
				</dd>
			</div>

			<div class="summary__row">
				<dt>Then</dt>
				<dd>
					{#if stepLines.length === 0}
						<span class="summary__muted">No steps yet</span>
					{:else}
						<ol class="summary__timeline">
							{#each stepLines as line, index (index)}
								<li>{line}</li>
							{/each}
						</ol>
					{/if}
				</dd>
			</div>

			<div class="summary__row">
				<dt>Stop when</dt>
				<dd>
					{#if definition.stops.length === 0}
						<span class="summary__muted">No stop conditions</span>
					{:else}
						{definition.stops.length}
						{definition.stops.length === 1 ? 'condition' : 'conditions'} chosen
					{/if}
				</dd>
			</div>
		</dl>

		<div class="summary__meta">
			<span class="summary__meta-label">Most emails one customer could get</span>
			<span class="summary__meta-value">{maxMessages}</span>
		</div>
	</div>
</SectionBlock>

<style lang="scss">
	.summary {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
		}

		&__row {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
				text-transform: uppercase;
				letter-spacing: 0.02em;
			}

			dd {
				margin: 0;
				color: var(--color-text);
			}
		}

		&__muted {
			color: var(--color-text--secondary);
			font-style: italic;
		}

		&__inline-list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			padding-left: var(--space-base);
			list-style: disc;
		}

		&__timeline {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding-left: var(--space-base);
			list-style: decimal;
		}

		&__meta {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__meta-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__meta-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
	}
</style>
