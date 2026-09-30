<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import type { DraftDifference } from '$lib/jafar/packages';

	// Shown when this tab tries to save a draft that another tab saved after it was opened. Nothing was
	// written; Jafar compares the two versions and chooses which one to keep.
	let {
		open,
		differences,
		savedBy,
		savedAt,
		pending = false,
		onKeepMine,
		onUseSaved,
		onClose
	}: {
		open: boolean;
		differences: DraftDifference[];
		savedBy: string | null;
		savedAt: string | null;
		pending?: boolean;
		onKeepMine: () => void;
		onUseSaved: () => void;
		onClose: () => void;
	} = $props();

	const savedWhen = $derived(
		savedAt
			? new Date(savedAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
			: ''
	);
</script>

<Dialog {open} title="This draft changed in another tab" size="large" {onClose}>
	<div class="draft-conflict">
		<p class="draft-conflict__intro">
			Your changes were not saved. {savedBy ? `${savedBy} saved` : 'Someone saved'} this draft{savedWhen
				? ` on ${savedWhen}`
				: ''}, after you opened it. Compare the two versions and choose which one to keep.
		</p>
		<div class="draft-conflict__table-wrap">
			<table class="draft-conflict__table">
				<thead>
					<tr>
						<th scope="col">What</th>
						<th scope="col">Your version</th>
						<th scope="col">Saved version</th>
					</tr>
				</thead>
				<tbody>
					{#each differences as difference (difference.field)}
						<tr>
							<th scope="row">{difference.label}</th>
							<td>{difference.mine}</td>
							<td>{difference.saved}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
		<div class="draft-conflict__actions">
			<Button variant="secondary" disabled={pending} onclick={onUseSaved}
				>Use the saved version</Button
			>
			<Button loading={pending} onclick={onKeepMine}>Keep my version</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.draft-conflict {
		display: grid;
		gap: var(--space-base);

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
		}

		&__table-wrap {
			overflow-x: auto;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__table {
			width: 100%;
			border-collapse: collapse;
			font-size: var(--typography--fontSize-small);

			th,
			td {
				padding: var(--space-small) var(--space-slim);
				border-top: var(--border-base) solid var(--color-border);
				text-align: start;
				vertical-align: top;
				line-height: var(--typography--lineHeight-base);
			}

			thead th {
				border-top: 0;
				color: var(--color-text--secondary);
				background: var(--color-surface--background);
				font-weight: 600;
			}

			tbody th {
				color: var(--color-heading);
				font-weight: 600;
				white-space: nowrap;
			}
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
