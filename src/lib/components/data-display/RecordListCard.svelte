<script lang="ts">
	import type { Snippet } from 'svelte';

	// The card a record list sits in: a title with a one-line subtitle (what the list is and how it is
	// ordered), a toolbar beside them for search and filters, then the table — or its loading, empty or
	// error state — and, inside the table, a footer for "Load more". Pair it with
	// `<DataTable variant="card">`, `<FilterChip variant="toolbar">`, `<DateRangeChip>` and
	// `<ListLoadMore variant="card">`.
	let {
		title,
		subtitle,
		headingIcon,
		toolbar,
		padBody = false,
		children
	}: {
		title: string;
		subtitle?: string;
		/** Optional decorative tile before the list heading. */
		headingIcon?: Snippet;
		/** Search and filter controls, drawn at the end of the header row. */
		toolbar?: Snippet;
		/** Pads the body, for a loading, empty or error state. A table runs edge to edge, so leave it off. */
		padBody?: boolean;
		children: Snippet;
	} = $props();

	const uid = $props.id();
	const titleId = `${uid}-title`;
</script>

<section class="record-list-card" aria-labelledby={titleId}>
	<header class="record-list-card__header">
		{#if headingIcon}<div class="record-list-card__heading-icon" aria-hidden="true">
				{@render headingIcon()}
			</div>{/if}
		<div class="record-list-card__heading">
			<h2 id={titleId}>{title}</h2>
			{#if subtitle}<p>{subtitle}</p>{/if}
		</div>
		{#if toolbar}<div class="record-list-card__toolbar">{@render toolbar()}</div>{/if}
	</header>
	<div class={['record-list-card__body', padBody && 'record-list-card__body--padded']}>
		{@render children()}
	</div>
</section>

<style lang="scss">
	.record-list-card {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__header {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: 18px var(--space-large);
		}
		&__heading-icon {
			flex: 0 0 auto;
		}
		&__header:has(.record-list-card__heading-icon) &__heading {
			flex: 1;
		}
		&__heading {
			display: grid;
			gap: 3px;

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
				letter-spacing: -0.2px;
			}
			p {
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}
		&__toolbar {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
		&__body--padded {
			padding: 0 var(--space-large) var(--space-large);
		}
	}
</style>
