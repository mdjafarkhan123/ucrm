<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { FactRow } from './paperwork-ui';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';

	// What a paperwork set says, one fact a row (`concept.pen` board `A0URqF`: Check and send, What you sent): a
	// 32 tile, the label over the value, and Change at the right while the set can still change. A document the
	// phone company sent back sits on the critical surface with Replace.
	let {
		facts,
		onChange,
		onlyFixes = false,
		disabled = false
	}: {
		facts: FactRow[];
		/** Missing on a set the phone company has: nothing can change. */
		onChange?: (step: 'details' | 'documents') => void;
		/** A sent-back set offers Replace on what was sent back, and nothing else. */
		onlyFixes?: boolean;
		disabled?: boolean;
	} = $props();

	const anchored = $derived(
		new Set(
			facts
				.filter((fact, index) => facts.findIndex((other) => other.step === fact.step) === index)
				.map((fact) => fact.key)
		)
	);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<dl class="paperwork-facts">
	{#each facts as fact (fact.key)}
		<div
			class={['paperwork-facts__row', fact.needsFix && 'paperwork-facts__row--fix']}
			id={anchored.has(fact.key) ? `paperwork-fact-${fact.step}` : undefined}
			tabindex={anchored.has(fact.key) ? -1 : undefined}
		>
			<IconTile icon={fact.icon} tone={fact.tone} size={32} white={fact.needsFix} />
			<span class="paperwork-facts__copy">
				<dt>{fact.label}</dt>
				<dd>{fact.value}</dd>
			</span>
			{#if onChange && fact.step !== 'start' && (!onlyFixes || fact.needsFix)}
				{@const step = fact.step}
				{#if fact.needsFix}
					<Button variant="secondary" size="small" {disabled} onclick={() => onChange(step)}>
						<span aria-hidden="true">{@html uploadIcon}</span>
						Replace
					</Button>
				{:else}
					<button
						type="button"
						class="paperwork-facts__change"
						{disabled}
						aria-label={`Change ${fact.label.toLowerCase()}`}
						onclick={() => onChange(step)}>Change</button
					>
				{/if}
			{/if}
		</div>
	{/each}
</dl>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-facts {
		margin: 0;

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-medium);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: -2px;
			}

			&--fix {
				background: var(--color-critical--surface);

				dt {
					color: var(--color-critical--onSurface) !important;
				}
			}
		}

		&__change {
			padding: var(--space-smaller) var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-interactive);
			font: inherit;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:active {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}

			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}
		}

		&__copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
				overflow-wrap: anywhere;
			}
		}
	}
</style>
