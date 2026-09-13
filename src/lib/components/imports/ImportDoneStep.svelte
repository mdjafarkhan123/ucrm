<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		fetchImportStatus,
		importStatusKey,
		type ImportCounts,
		type ImportStatus
	} from '$lib/imports/api';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	let {
		batchId,
		sourceFilename,
		initialStatus,
		initialCounts,
		clientsHref
	}: {
		batchId: string;
		sourceFilename: string;
		initialStatus: ImportStatus;
		initialCounts: ImportCounts;
		clientsHref: string;
	} = $props();

	// Client creation runs in a background worker after commit, so poll the batch until it settles. placeholder
	// data renders the screen instantly from what commit returned; a real fetch still runs on mount to pick up
	// the accurate error-file flag, and keeps running every 1.5s while the status is still 'importing'.
	//
	// The worker flips the batch to 'completed' and then stamps the error file a moment later, so on a batch
	// that has held/errored rows we keep polling a few extra times after completion until the file appears --
	// bounded, so a file that never lands (a rare generation failure) can't poll forever.
	const settle = { extraPolls: 0 };
	const statusQuery = createQuery(() => ({
		queryKey: importStatusKey(batchId),
		queryFn: () => fetchImportStatus(batchId),
		placeholderData: {
			batch_id: batchId,
			source_filename: sourceFilename,
			row_count: null,
			status: initialStatus,
			counts: initialCounts,
			has_error_file: false
		},
		refetchInterval: (query) => {
			const data = query.state.data;
			if (!data || data.status === 'importing') return 1500;
			const expectsErrorFile = data.counts.held + data.counts.error > 0;
			if (expectsErrorFile && !data.has_error_file && settle.extraPolls < 6) {
				settle.extraPolls += 1;
				return 1500;
			}
			return false;
		}
	}));

	const status = $derived(statusQuery.data?.status ?? initialStatus);
	const counts = $derived(statusQuery.data?.counts ?? initialCounts);
	const importing = $derived(status === 'importing');
	const failed = $derived(status === 'failed');
	const attention = $derived(counts.held + counts.error);
	const added = $derived(counts.created);
	const updated = $derived(counts.updated);
	const totalIn = $derived(added + updated);
	const hasErrorFile = $derived(statusQuery.data?.has_error_file ?? false);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="panel">
	<header class="panel__head">
		<h2>
			{importing ? 'Bringing your clients in' : failed ? "Import didn't finish" : 'Import complete'}
		</h2>
		<p>{sourceFilename}</p>
	</header>

	<div class="panel__body">
		<div class="hero">
			<span
				class="hero__ring hero__ring--{importing ? 'busy' : failed ? 'error' : 'ok'}"
				aria-hidden="true"
			>
				{#if importing}
					<span class="hero__spin">{@html loaderIcon}</span>
				{:else if failed}
					{@html alertIcon}
				{:else}
					{@html checkIcon}
				{/if}
			</span>
			<div>
				{#if importing}
					<h3>Finishing up…</h3>
					<p>
						This usually takes under a minute. You can leave this page — the import keeps going.
					</p>
				{:else if failed}
					<h3>Something went wrong.</h3>
					<p>No partial data was left behind. Please try the import again.</p>
				{:else}
					<h3>{totalIn} {totalIn === 1 ? 'client is' : 'clients are'} in.</h3>
					<p>
						{added} added, {updated} updated. {counts.skipped} duplicates skipped. {counts.error} failed.
					</p>
				{/if}
			</div>
		</div>

		{#if !failed}
			<div class="tiles">
				<div class="tile tile--create">
					<div class="tile__n">{added}</div>
					<div class="tile__k">New clients added</div>
				</div>
				<div class="tile tile--update">
					<div class="tile__n">{updated}</div>
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
		{/if}

		{#if !importing && hasErrorFile}
			<div class="callout">
				<p>
					<b>{attention} {attention === 1 ? 'row needs' : 'rows need'} a fix.</b>
					Download the list, correct {attention === 1 ? 'it' : 'them'} in your spreadsheet, and import
					again — nothing already added will be duplicated.
				</p>
				<a class="download-btn" href={`/api/imports/clients/${batchId}/error-file`} download>
					<span class="btn-icon" aria-hidden="true">{@html downloadIcon}</span>
					Download the {attention}
					{attention === 1 ? 'row' : 'rows'} to fix
				</a>
			</div>
		{:else if !importing && !failed && attention > 0}
			<!-- Terminal, rows need attention, but the worker is still stamping the downloadable list. -->
			<div class="callout">
				<p>Preparing your list of {attention} {attention === 1 ? 'row' : 'rows'} to fix…</p>
			</div>
		{:else if !importing && !failed}
			<div class="callout callout--calm">
				<p>
					<b>Safe to run again.</b> Re-importing this same file changes nothing — no duplicates.
				</p>
			</div>
		{/if}
	</div>

	<footer class="panel__foot">
		<span class="foot-hint">These clients are now in your Clients list.</span>
		<Button variant="primary" href={clientsHref} disabled={importing}>View clients</Button>
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

			:global(svg) {
				width: 28px;
				height: 28px;
			}
			&--ok {
				background: var(--color-success--surface);
				color: var(--color-success--onSurface);
			}
			&--busy {
				background: var(--color-informative--surface);
				color: var(--color-informative--onSurface);
			}
			&--error {
				background: var(--color-critical--surface);
				color: var(--color-critical--onSurface);
			}
		}

		&__spin {
			display: grid;
			place-items: center;
			animation: import-spin 0.9s linear infinite;
		}
	}

	@keyframes import-spin {
		to {
			transform: rotate(360deg);
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
		text-decoration: none;
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
