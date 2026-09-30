<script lang="ts">
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import type { DraftLine, PublishProblem } from '$lib/jafar/packages';

	// Package builder P7: Jafar reviews the exact saved draft before it becomes the next edition. Lines that
	// differ from the current edition are marked, and the consequences for customers and sign-up are spelled
	// out. Problems the database found are listed instead of publishing (ADR 0003 decisions 2 and 4).
	let {
		open,
		editionNumber,
		lines,
		changedFields,
		previousEditionNumber,
		customerCount,
		listing,
		problems,
		pending = false,
		onPublish,
		onClose
	}: {
		open: boolean;
		editionNumber: number;
		lines: DraftLine[];
		/** Fields that differ from the published edition; empty when there is none. */
		changedFields: Set<string>;
		previousEditionNumber: number | null;
		customerCount: number;
		listing: 'public' | 'private' | 'archived';
		problems: PublishProblem[];
		pending?: boolean;
		onPublish: () => void;
		onClose: () => void;
	} = $props();

	const nothingChanged = $derived(previousEditionNumber !== null && changedFields.size === 0);
</script>

<Dialog {open} title={`Publish edition ${editionNumber}?`} size="large" {onClose}>
	<div class="package-publish">
		<ul class="package-publish__effects">
			<li>
				These are the saved terms. Once published they cannot change; a later change becomes a new
				edition.
			</li>
			{#if previousEditionNumber !== null}
				<li>
					{customerCount === 0
						? `Edition ${previousEditionNumber} has no customers, so nobody is affected.`
						: `${customerCount} ${customerCount === 1 ? 'customer stays' : 'customers stay'} on their current edition until you move them. Their price and features do not change.`}
				</li>
			{/if}
			<li>
				{listing === 'public'
					? 'New customers can choose it on sign-up straight away. You will be reminded to update your marketing site.'
					: listing === 'archived'
						? 'The package is archived, so new customers still cannot choose it until you restore it.'
						: 'It stays private: only you can assign it to a customer.'}
			</li>
		</ul>

		{#if problems.length}
			<Banner type="error">
				<p>This draft cannot be published yet:</p>
				<ul class="package-publish__problems">
					{#each problems as problem (problem.code + (problem.key ?? ''))}
						<li>{problem.message}</li>
					{/each}
				</ul>
			</Banner>
		{:else if nothingChanged}
			<Banner type="notice">
				<p>
					These terms are the same as edition {previousEditionNumber}. Publishing them still creates
					a new edition.
				</p>
			</Banner>
		{/if}

		<div class="package-publish__table-wrap">
			<table class="package-publish__table" aria-label={`Terms of edition ${editionNumber}`}>
				<tbody>
					{#each lines as line (line.field)}
						<tr>
							<th scope="row">{line.label}</th>
							<td>
								{line.value}
								{#if changedFields.has(line.field)}
									<Badge status="informative" size="small" dot={false}>Changed</Badge>
								{/if}
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>

		<div class="package-publish__actions">
			<Button variant="secondary" disabled={pending} onclick={onClose}>Cancel</Button>
			<Button loading={pending} disabled={problems.length > 0} onclick={onPublish}
				>Publish edition {editionNumber}</Button
			>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.package-publish {
		display: grid;
		gap: var(--space-base);

		&__effects {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding-inline-start: var(--space-large);
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
		}

		&__problems {
			margin: var(--space-smaller) 0 0;
			padding-inline-start: var(--space-large);
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

			tr:first-child th,
			tr:first-child td {
				border-top: 0;
			}

			th {
				width: 30%;
				color: var(--color-heading);
				font-weight: 600;
			}

			td :global(.badge) {
				margin-inline-start: var(--space-smaller);
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
