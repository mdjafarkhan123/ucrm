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
		// Facts flow onto another line instead of squeezing a date onto two. Every fact carries its divider
		// and lead space; the list is pulled left by that much and its parent clips it, so whichever fact
		// starts a line sits flush with no stray divider.
		margin-left: -17px;
		&__row {
			position: relative;
			flex: 1 0 auto;
			max-width: calc(100% - 17px);
			min-height: 36px;
			flex-direction: column;
			align-items: flex-start;
			justify-content: center;
			gap: 2px;
			padding: 0 16px 0 62px;
			border: 0;
			border-left: 1px solid var(--classic2-divider);
			box-sizing: border-box;
		}
		&__row--number {
			display: none;
		}
		// Each fact leads with a soft tile; the first, the record's headline fact, carries the brand tint.
		&__icon {
			display: inline-flex;
			position: absolute;
			top: 50%;
			left: 16px;
			align-items: center;
			justify-content: center;
			box-sizing: border-box;
			width: 36px;
			height: 36px;
			border: 1px solid var(--classic2-border);
			border-radius: var(--classic2-radius-control);
			background: var(--classic2-surface-soft);
			color: var(--classic2-secondary);
			transform: translateY(-50%);
		}
		&__row:first-child .record-facts__icon,
		&__row--number + .record-facts__row .record-facts__icon {
			border-color: var(--classic2-green-soft);
			background: var(--classic2-green-tint);
			color: var(--classic2-green);
		}
		&__icon :global(svg) {
			width: 17px;
			height: 17px;
		}
		&__row dt {
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}
		&__row dd {
			max-width: 100%;
			margin: 0;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			overflow: hidden;
			text-align: left;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__row dd.record-facts__wrap {
			white-space: normal;
			overflow-wrap: anywhere;
		}
		&__row dd.record-facts__empty {
			color: var(--classic2-muted);
			font-weight: 400;
		}
	}
</style>
