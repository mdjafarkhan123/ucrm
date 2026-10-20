<script lang="ts">
	// The facts that identify a record, in the header card under the client line: up to four even columns
	// split by hairlines, each a small coloured tile and label over the value (Pencil "Record header · C").
	// Every record type has its own set, so this is a list, never fixed slots. A fact with nothing in it says
	// in grey what it is waiting for rather than showing a blank.
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { RecordFact } from './types';

	let { facts, class: className = '' }: { facts: RecordFact[]; class?: string } = $props();
</script>

<dl class={`record-facts ${className}`}>
	{#each facts as fact (fact.label)}
		<div class="record-facts__fact">
			<dt class="record-facts__label">
				{#if fact.icon}
					<IconTile icon={fact.icon} tone={fact.kind ?? 'time'} size={20} />
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
		display: grid;
		grid-auto-columns: minmax(0, 1fr);
		grid-auto-flow: column;
		margin: 0;

		&__fact {
			display: flex;
			flex-direction: column;
			gap: 6px;
			min-width: 0;

			& + & {
				padding-left: var(--space-base);
				border-left: var(--border-base) solid var(--color-border);
			}
		}

		&__label {
			display: flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
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
			grid-auto-flow: row;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			row-gap: var(--space-base);

			&__fact:nth-child(odd) {
				padding-left: 0;
				border-left: 0;
			}
		}
	}
</style>
