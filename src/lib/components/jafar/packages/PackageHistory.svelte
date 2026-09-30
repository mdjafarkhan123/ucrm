<script lang="ts">
	import { describeCatalogEvent, type CatalogEvent } from '$lib/jafar/packages';

	// Package builder P7: what happened to a package in the catalog, newest first. Shows the latest few and
	// expands to the rest, which the builder already loaded (the reader caps it at 100).
	let { events }: { events: CatalogEvent[] } = $props();

	const collapsedCount = 6;
	let expanded = $state(false);
	const shown = $derived(expanded ? events : events.slice(0, collapsedCount));

	function formatDate(value: string) {
		return new Date(value).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
	}
</script>

{#if events.length === 0}
	<p class="package-history__empty">Nothing has happened to this package yet.</p>
{:else}
	<ol class="package-history">
		{#each shown as event (event.id)}
			<li class="package-history__item">
				<span class="package-history__what">{describeCatalogEvent(event)}</span>
				<span class="package-history__when"
					>{formatDate(event.created_at)}{event.actor_email ? ` · ${event.actor_email}` : ''}</span
				>
			</li>
		{/each}
	</ol>
	{#if events.length > collapsedCount}
		<button
			type="button"
			class="package-history__toggle"
			aria-expanded={expanded}
			onclick={() => (expanded = !expanded)}
			>{expanded ? 'Show less' : `Show all ${events.length}`}</button
		>
	{/if}
{/if}

<style lang="scss">
	.package-history {
		display: grid;
		gap: var(--space-slim);
		margin: 0;
		padding: 0;
		list-style: none;

		&__item {
			display: grid;
			gap: var(--space-smallest);
			padding-inline-start: var(--space-slim);
			border-inline-start: var(--border-thick) solid var(--color-border);
		}

		&__what {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__when,
		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			overflow-wrap: anywhere;
		}

		&__toggle {
			justify-self: start;
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: none;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: none;
				border-radius: var(--radius-small);
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
