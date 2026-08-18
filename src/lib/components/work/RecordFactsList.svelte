<script lang="ts">
	// The short list of dates and numbers that identify a work record, sitting beside the client card in
	// the header. Every record type has a different set — a quote shows Quote # / Created / Approved, a
	// request shows Requested / Assessment — so this is a list of rows, never a fixed pair of slots.
	//
	// A row with nothing in it says what it is waiting for rather than showing a blank line.
	import type { RecordFact } from './types';

	let { facts, class: className = '' }: { facts: RecordFact[]; class?: string } = $props();
</script>

<dl class={`record-facts ${className}`}>
	{#each facts as fact (fact.label)}
		<div class="record-facts__row">
			<dt>{fact.label}</dt>
			{#if fact.value}
				<dd>{fact.value}</dd>
			{:else}
				<dd class="record-facts__empty">{fact.empty ?? '—'}</dd>
			{/if}
		</div>
	{/each}
</dl>

<style lang="scss">
	.record-facts {
		display: flex;
		flex-direction: column;

		&__row {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			dt {
				color: var(--color-text--secondary);
			}

			dd {
				overflow: hidden;
				color: var(--color-heading);
				font-weight: 600;
				text-align: right;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}

		&__empty {
			color: var(--color-text--secondary);
			font-weight: 400;
		}
	}
</style>
