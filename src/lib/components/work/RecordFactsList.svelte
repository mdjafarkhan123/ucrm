<script lang="ts">
	// The facts that identify a record, in the header card under the client line: up to four facts in one row
	// split by hairlines, each a coloured tile at the left with its label over the value beside it (Pencil
	// "Record header · C · White top"). Each fact takes the room its words need and the spare room goes between
	// them. Every record type has its own set, so this is a list, never fixed slots. A fact with nothing in it
	// says in grey what it is waiting for rather than showing a blank.
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { RecordFact } from './types';

	let { facts, class: className = '' }: { facts: RecordFact[]; class?: string } = $props();
</script>

<dl class={`record-facts ${className}`}>
	{#each facts as fact (fact.label)}
		<div class="record-facts__fact" class:record-facts__fact--tile={!!fact.icon}>
			<dt class="record-facts__label">
				{#if fact.icon}
					<IconTile
						icon={fact.icon}
						tone={fact.kind ?? 'time'}
						size={40}
						class="record-facts__tile"
					/>
				{/if}
				{fact.label}
			</dt>
			<dd class:record-facts__quiet={!fact.value || fact.quiet} title={fact.value ?? undefined}>
				{#if !fact.value}{fact.empty ?? '—'}{:else if fact.href}
					<!-- The caller builds the link (tel:, mailto:); nothing here is an app route. -->
					<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
					<a href={fact.href}>{fact.value}</a>
				{:else}{fact.value}{/if}
			</dd>
		</div>
	{/each}
</dl>

<style lang="scss">
	.record-facts {
		display: flex;
		justify-content: space-between;
		gap: var(--space-large);
		margin: 0;

		// The tile sits in the fact's own left gutter, so the label and value stay a plain dt/dd pair.
		&__fact {
			--fact-inset: 0px;
			position: relative;
			display: flex;
			flex: 0 1 auto;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
			padding-left: var(--fact-inset);

			& + & {
				--fact-inset: var(--space-medium);
				border-left: var(--border-base) solid var(--color-border);
			}

			&--tile {
				min-height: 40px;
				padding-left: calc(var(--fact-inset) + 40px + var(--space-slim));
			}
		}

		:global(.record-facts__tile) {
			position: absolute;
			top: 0;
			left: var(--fact-inset);
		}

		&__label {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		dd {
			overflow: hidden;
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;

			a {
				color: inherit;
				text-decoration: none;

				&:hover {
					color: var(--color-interactive);
					text-decoration: underline;
				}
			}
		}

		dd.record-facts__quiet {
			color: var(--color-text--secondary);
		}
	}

	// Two facts a row on a phone, the hairline only between the pair.
	@media (max-width: 767px) {
		.record-facts {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);

			&__fact:nth-child(odd) {
				--fact-inset: 0px;
				border-left: 0;
			}
		}
	}
</style>
