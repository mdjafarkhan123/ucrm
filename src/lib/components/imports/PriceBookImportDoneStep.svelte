<script lang="ts">
	import Papa from 'papaparse';
	import Button from '$lib/components/ui/Button.svelte';
	import type { CatalogErrorRow, CatalogImportCounts } from '$lib/imports/catalog-api';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	// The Price Book import's Done step. Unlike the client importer's, this one never polls: Commit ran
	// synchronously and already returned the final counts, so there is nothing left to wait for. "Download
	// rows to fix" builds its CSV from data already in memory (no stored batch, no server route) and hands
	// the browser a normal file download.
	let {
		sourceFilename,
		counts,
		errorRows,
		priceBookHref
	}: {
		sourceFilename: string;
		counts: CatalogImportCounts;
		errorRows: CatalogErrorRow[];
		priceBookHref: string;
	} = $props();

	const attention = $derived(counts.held + counts.error);
	const totalIn = $derived(counts.created + counts.updated);

	function downloadErrors() {
		const csv = Papa.unparse(
			errorRows.map((row) => ({ Row: row.source_row_number, Problem: row.reason })),
			{ columns: ['Row', 'Problem'] }
		);
		const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
		const url = URL.createObjectURL(blob);
		const link = document.createElement('a');
		link.href = url;
		link.download = 'price-book-import-errors.csv';
		link.click();
		URL.revokeObjectURL(url);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="panel">
	<header class="panel__head">
		<h2>Import complete</h2>
		<p>{sourceFilename}</p>
	</header>

	<div class="panel__body">
		<div class="hero">
			<span class="hero__ring" aria-hidden="true">{@html checkIcon}</span>
			<div>
				<h3>{totalIn} {totalIn === 1 ? 'item is' : 'items are'} in.</h3>
				<p>
					{counts.created} added, {counts.updated} updated. {counts.skipped} duplicates skipped.
					{counts.error} failed.
				</p>
			</div>
		</div>

		<div class="tiles">
			<div class="tile tile--create">
				<div class="tile__n">{counts.created}</div>
				<div class="tile__k">New items added</div>
			</div>
			<div class="tile tile--update">
				<div class="tile__n">{counts.updated}</div>
				<div class="tile__k">Existing updated</div>
			</div>
			<div class="tile tile--skip">
				<div class="tile__n">{counts.skipped}</div>
				<div class="tile__k">Duplicates skipped</div>
			</div>
			<div class="tile tile--attention">
				<div class="tile__n">{attention}</div>
				<div class="tile__k">Need your attention</div>
			</div>
		</div>

		{#if attention > 0}
			<div class="callout">
				<p>
					<b>{attention} {attention === 1 ? 'row needs' : 'rows need'} a fix.</b>
					Download the list, correct {attention === 1 ? 'it' : 'them'} in your spreadsheet, and import
					again — nothing already added will be duplicated.
				</p>
				<button type="button" class="download-btn" onclick={downloadErrors}>
					<span class="btn-icon" aria-hidden="true">{@html downloadIcon}</span>
					Download the {attention}
					{attention === 1 ? 'row' : 'rows'} to fix
				</button>
			</div>
		{:else}
			<div class="callout callout--calm">
				<p>
					<b>Safe to run again.</b> Re-importing this same file changes nothing — no duplicates.
				</p>
			</div>
		{/if}
	</div>

	<footer class="panel__foot">
		<span class="foot-hint">These items are now in your Price Book.</span>
		<Button variant="primary" href={priceBookHref}>View Price Book</Button>
	</footer>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			padding: var(--space-large);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	.hero {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		margin-bottom: var(--space-large);

		h3 {
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-larger);
			font-weight: 600;
			color: var(--color-heading);
			margin: 0;
		}
		p {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
		}

		&__ring {
			flex: none;
			width: 54px;
			height: 54px;
			border-radius: var(--radius-circle);
			display: grid;
			place-items: center;
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);

			:global(svg) {
				width: 28px;
				height: 28px;
			}
		}
	}

	.tiles {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
		gap: var(--space-slim);
		margin-bottom: var(--space-large);
	}

	.tile {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		padding: var(--space-base);
		background: var(--color-surface);
		position: relative;
		overflow: hidden;

		&::before {
			content: '';
			position: absolute;
			left: 0;
			top: 0;
			bottom: 0;
			width: 4px;
			background: var(--accent, var(--color-border--section));
		}
		&--create {
			--accent: var(--color-success);
		}
		&--update {
			--accent: var(--color-informative);
		}
		&--skip {
			--accent: var(--color-disabled);
		}
		&--attention {
			--accent: var(--color-warning);
		}

		&__n {
			font-family: var(--typography--fontFamily-display);
			font-weight: 600;
			font-size: var(--typography--fontSize-largest);
			color: var(--color-heading);
			line-height: 1;
		}
		&__k {
			font-size: var(--typography--fontSize-small);
			color: var(--color-text--secondary);
			margin-top: var(--space-small);
		}
	}

	.callout {
		display: flex;
		align-items: center;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: var(--space-slim);
		background: var(--color-warning--surface);
		border-radius: var(--radius-base);
		padding: var(--space-base);

		&--calm {
			background: var(--color-success--surface);
		}
		p {
			margin: 0;
			font-size: var(--typography--fontSize-small);
			color: var(--color-warning--onSurface);
			max-width: 52ch;
		}
		&--calm p {
			color: var(--color-success--onSurface);
		}
		b {
			font-weight: 600;
		}
	}

	.download-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		font-family: var(--typography--fontFamily-normal);
		font-weight: 600;
		font-size: var(--typography--fontSize-base);
		color: var(--color-heading);
		background: var(--color-surface);
		border: 1px solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		padding: var(--space-small) var(--space-base);
		cursor: pointer;
		white-space: nowrap;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.foot-hint {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
