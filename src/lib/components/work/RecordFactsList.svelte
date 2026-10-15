<script lang="ts">
	// The short list of dates and numbers that identify a work record, sitting beside the client card in
	// the header. Every record type has a different set — a quote shows Quote # / Created / Approved, a
	// request shows Requested / Assessment — so this is a list of rows, never a fixed pair of slots.
	//
	// A row with nothing in it says what it is waiting for rather than showing a blank line.
	import type { RecordFact } from './types';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';

	let { facts, class: className = '' }: { facts: RecordFact[]; class?: string } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<dl class={`record-facts ${className}`}>
	{#each facts as fact (fact.label)}
		<div class="record-facts__row" class:record-facts__row--number={fact.label.endsWith(' #')}>
			<dt>
				<span class="record-facts__icon" aria-hidden="true"
					>{@html /created|requested|assessment|date|due|sent|viewed|issued|approved|declined|received/i.test(
						fact.label
					)
						? calendarIcon
						: /#|version/i.test(fact.label)
							? hashIcon
							: listIcon}</span
				>{fact.label}
			</dt>
			{#if fact.value}
				<dd class:record-facts__wrap={fact.wrap}>{fact.value}</dd>
			{:else}
				<dd class="record-facts__empty">{fact.empty ?? '—'}</dd>
			{/if}
		</div>
	{/each}
</dl>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.record-facts {
		display: flex;
		flex-direction: column;
		&__icon {
			display: none;
		}

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

		&__wrap {
			overflow: visible;
			white-space: normal;
			overflow-wrap: anywhere;
		}
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .record-facts {
		flex-direction: row;
		flex-wrap: wrap;
		gap: 12px 0;
		margin: 0;
		&__row {
			flex: 1 1 120px;
			min-width: 0;
			flex-direction: column;
			align-items: flex-start;
			justify-content: flex-start;
			gap: 3px;
			padding: 0 16px;
			border: 0;
			border-left: 1px solid var(--classic2-divider);
		}
		&__row--number {
			display: none;
		}
		&__row--number + .record-facts__row,
		&__row:first-child {
			padding-left: 0;
			border-left: 0;
		}
		&__icon {
			display: inline-flex;
			color: var(--classic2-icon-muted);
		}
		&__icon :global(svg) {
			width: 14px;
			height: 14px;
		}
		&__row dt {
			display: flex;
			align-items: center;
			gap: 6px;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
		}
		&__row dd {
			max-width: 100%;
			margin: 0;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			text-align: left;
			white-space: normal;
			overflow-wrap: anywhere;
		}
		&__row dd.record-facts__empty {
			color: var(--classic2-muted);
			font-weight: 400;
		}
	}
</style>
