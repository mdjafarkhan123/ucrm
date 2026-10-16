<script lang="ts">
	// The short list of dates and numbers that identify a work record, sitting beside the client card in
	// the header. Every record type has a different set — a quote shows Quote # / Created / Approved, a
	// request shows Requested / Assessment — so this is a list of rows, never a fixed pair of slots.
	//
	// A row with nothing in it says what it is waiting for rather than showing a blank line.
	import type { RecordFact } from './types';

	let {
		facts,
		neutralIcons = false,
		class: className = ''
	}: {
		facts: RecordFact[];
		/** App look: every icon tile is the same quiet colour, instead of the first one being green. */
		neutralIcons?: boolean;
		class?: string;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<dl class={`record-facts ${className}`} class:record-facts--neutral={neutralIcons}>
	{#each facts as fact (fact.label)}
		<div class="record-facts__row" class:record-facts__row--fixed={fact.fixed}>
			{#if fact.icon}<span
					class={['record-facts__icon', fact.tone && `record-facts__icon--${fact.tone}`]}
					aria-hidden="true">{@html fact.icon}</span
				>{/if}
			<dt>{fact.label}</dt>
			{#if fact.value}
				<dd class:record-facts__wrap={fact.wrap} class:record-facts__quiet={fact.quiet}>
					{#if fact.href}
						<!-- The caller builds the link (tel:, mailto:); nothing here is an app route. -->
						<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
						<a class="record-facts__link" href={fact.href}>{fact.value}</a>
					{:else}{fact.value}{/if}
				</dd>
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

		&__quiet {
			color: var(--color-text--secondary);
		}

		&__link {
			color: inherit;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__wrap {
			overflow: visible;
			white-space: normal;
			overflow-wrap: anywhere;
		}

		&__icon {
			display: none;
		}
	}

	// App look: the facts become a strip of columns under the client row — a small icon tile, the label
	// above, the value below — with a hairline between columns.
	:global(.record-detail--cards) .record-facts {
		display: flex;
		flex-flow: row nowrap;
		align-items: center;
		gap: 16px 0;

		.record-facts__row {
			display: grid;
			flex: 1 1 auto;
			align-content: center;
			align-items: center;
			min-width: 0;
			row-gap: 2px;
			padding: 0 16px;
			column-gap: 10px;
			grid-template-columns: auto minmax(0, 1fr);

			& + .record-facts__row {
				border-top: 0;
				border-left: var(--border-base) solid var(--color-border);
			}
			&:first-child {
				padding-left: 0;
			}
			&.record-facts__row--fixed {
				flex-shrink: 0;
			}
			dt {
				white-space: nowrap;
				grid-column: 2;
				grid-row: 1;
				font-size: var(--typography--fontSize-small);
				font-weight: 500;
			}
			dd {
				grid-column: 2;
				grid-row: 2;
				font-size: var(--typography--fontSize-base);
				text-align: left;
			}
		}
		.record-facts__icon {
			display: inline-grid;
			width: 36px;
			height: 36px;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: var(--color-surface--background--subtle);
			grid-column: 1;
			grid-row: 1 / span 2;

			:global(svg) {
				width: 17px;
				height: 17px;
			}
		}
		&:not(.record-facts--neutral) .record-facts__row:first-child .record-facts__icon {
			color: var(--color-interactive);
			background: var(--color-success--surface);
		}
		// A page that names a tone per fact overrides the first-fact default above.
		.record-facts__icon--neutral,
		.record-facts__row:first-child .record-facts__icon--neutral {
			color: var(--color-icon--secondary);
			background: var(--color-surface--background--subtle);
		}
		.record-facts__icon--success,
		.record-facts__row:first-child .record-facts__icon--success {
			color: var(--color-interactive);
			background: var(--color-success--surface);
		}
		.record-facts__icon--warning,
		.record-facts__row:first-child .record-facts__icon--warning {
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
		}
		.record-facts__empty {
			font-weight: 600;
		}
	}

	// A narrower laptop leaves the header too little room for four columns: two by two, no hairlines.
	@media (max-width: 1359px) {
		:global(.record-detail--cards) .record-facts {
			display: grid;
			gap: 16px 24px;
			grid-template-columns: repeat(2, minmax(0, 1fr));

			.record-facts__row,
			.record-facts__row + .record-facts__row {
				padding: 0;
				border-left: 0;
			}
			dd {
				overflow: visible;
				white-space: normal;
				overflow-wrap: anywhere;
			}
		}
	}
</style>
