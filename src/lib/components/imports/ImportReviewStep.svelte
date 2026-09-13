<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import type { ReviewSummary } from '$lib/imports/api';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	let {
		summary,
		rowCount,
		errorMessage = '',
		loading = false,
		onBack,
		onCommit
	}: {
		summary: ReviewSummary;
		rowCount: number;
		errorMessage?: string;
		loading?: boolean;
		onBack: () => void;
		onCommit: () => void;
	} = $props();

	const attention = $derived(summary.hold + summary.error);
	const willImport = $derived(summary.create + summary.update);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="panel">
	<header class="panel__head">
		<h2>Here's what will happen</h2>
		<p>Review before anything is saved. {rowCount} rows in your file.</p>
	</header>

	<div class="panel__body">
		{#if errorMessage}
			<p class="form-error" role="alert">{@html alertIcon}<span>{errorMessage}</span></p>
		{/if}

		<div class="tiles">
			<div class="tile tile--create">
				<div class="tile__n">{summary.create}</div>
				<div class="tile__k">New clients</div>
			</div>
			<div class="tile tile--update">
				<div class="tile__n">{summary.update}</div>
				<div class="tile__k">Updates to existing</div>
			</div>
			<div class="tile tile--skip">
				<div class="tile__n">{summary.skip}</div>
				<div class="tile__k">Duplicates skipped</div>
			</div>
			<div class="tile tile--attention">
				<div class="tile__n">{attention}</div>
				<div class="tile__k">Need your attention</div>
			</div>
		</div>

		{#if attention > 0}
			<p class="note">
				<span class="note__icon" aria-hidden="true">{@html alertIcon}</span>
				<span>
					{attention}
					{attention === 1 ? 'row needs' : 'rows need'} a decision — a shared phone, or a contact that
					matches two different clients. {attention === 1 ? 'It' : 'They'} won't be imported, and you'll
					get a file listing {attention === 1 ? 'it' : 'them'} to fix once the import finishes.
				</span>
			</p>
		{/if}

		<div class="callout">
			<span class="callout__icon" aria-hidden="true">{@html shieldIcon}</span>
			<p>
				<b>Nothing gets sent.</b> Importing never emails or texts your clients, and never starts automations,
				welcome messages, or review requests.
			</p>
		</div>
	</div>

	<footer class="panel__foot">
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<Button variant="primary" {loading} disabled={willImport === 0} onclick={onCommit}>
			{willImport === 0 ? 'Nothing to import' : `Import ${willImport} clients`}
			<span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
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

	.form-error {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		margin: 0 0 var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);

		:global(svg) {
			flex: none;
			width: 18px;
			height: 18px;
			margin-top: 1px;
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

	.note {
		display: flex;
		gap: var(--space-small);
		align-items: flex-start;
		margin: 0 0 var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);

		&__icon {
			flex: none;
			:global(svg) {
				width: 18px;
				height: 18px;
				display: block;
				margin-top: 1px;
			}
		}
	}

	.callout {
		display: flex;
		gap: var(--space-slim);
		align-items: flex-start;
		background: var(--color-success--surface);
		border-radius: var(--radius-base);
		padding: var(--space-base);

		&__icon {
			flex: none;
			color: var(--color-success--onSurface);
			:global(svg) {
				width: 20px;
				height: 20px;
				display: block;
				margin-top: 1px;
			}
		}
		p {
			margin: 0;
			font-size: var(--typography--fontSize-small);
			color: var(--color-success--onSurface);
		}
		b {
			font-weight: 600;
		}
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
