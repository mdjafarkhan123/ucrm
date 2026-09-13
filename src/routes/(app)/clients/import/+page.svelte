<script lang="ts">
	import { resolve } from '$app/paths';
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import ImportStepper from '$lib/components/imports/ImportStepper.svelte';
	import ImportUploadStep from '$lib/components/imports/ImportUploadStep.svelte';
	import ImportMapStep from '$lib/components/imports/ImportMapStep.svelte';
	import ImportReviewStep from '$lib/components/imports/ImportReviewStep.svelte';
	import ImportDoneStep from '$lib/components/imports/ImportDoneStep.svelte';
	import {
		autoMapHeaders,
		commitImport,
		ImportError,
		reviewImport,
		setImportMapping,
		uploadClientImport,
		type ColumnMapping,
		type ImportCounts,
		type ImportStatus,
		type MatchAction,
		type ReviewSummary,
		type UploadResult
	} from '$lib/imports/api';

	const queryClient = useQueryClient();
	const clientsHref = resolve('/(app)/clients');

	let step = $state(1);
	let matchAction = $state<MatchAction>('update');
	let file = $state<File | null>(null);
	let batch = $state<UploadResult | null>(null);
	let mapping = $state<ColumnMapping>({});
	let summary = $state<ReviewSummary | null>(null);
	let commitResult = $state<{ status: ImportStatus; counts: ImportCounts } | null>(null);

	let uploadError = $state('');
	let mapError = $state('');
	let reviewError = $state('');

	// The most useful message a failed call carries: the server puts the real reason on the offending field
	// (the file input, or the column mapping), so prefer that over the generic "please review" summary.
	function messageFrom(error: unknown, fallback: string): string {
		if (error instanceof ImportError) {
			return Object.values(error.fieldErrors)[0] ?? error.message ?? fallback;
		}
		return fallback;
	}

	const uploadMut = createMutation(() => ({
		mutationFn: () => {
			if (!file) throw new Error('Choose a CSV file to import.');
			return uploadClientImport(file);
		},
		onSuccess: (result) => {
			batch = result;
			mapping = autoMapHeaders(result.headers);
			uploadError = '';
			step = 2;
		},
		onError: (error) => {
			uploadError = messageFrom(error, 'That file could not be uploaded.');
		}
	}));

	// The Map step's one action does two calls: save the mapping + match action, then run the Review dry-run.
	const mapReviewMut = createMutation(() => ({
		mutationFn: async () => {
			if (!batch) throw new Error('Upload a file first.');
			await setImportMapping(batch.batch_id, {
				column_mapping: mapping,
				match_action: matchAction
			});
			return reviewImport(batch.batch_id);
		},
		onSuccess: (result) => {
			summary = result.summary;
			mapError = '';
			step = 3;
		},
		onError: (error) => {
			mapError = messageFrom(error, 'That import could not be reviewed.');
		}
	}));

	const commitMut = createMutation(() => ({
		mutationFn: () => {
			if (!batch) throw new Error('Upload a file first.');
			return commitImport(batch.batch_id);
		},
		onSuccess: (result) => {
			commitResult = { status: result.status, counts: result.counts };
			reviewError = '';
			// The freshly imported clients belong in every clients list the moment we land on the Done screen.
			void queryClient.invalidateQueries({ queryKey: ['clients', 'list'] });
			step = 4;
		},
		onError: (error) => {
			reviewError = messageFrom(error, 'That import could not be started.');
		}
	}));

	function onFile(next: File | null) {
		file = next;
		// A new file invalidates any batch built from the previous one, so Continue re-uploads.
		batch = null;
		summary = null;
		uploadError = '';
	}

	function onContinue() {
		// Re-entering the Upload step and pressing Continue without changing the file reuses the batch we
		// already have, rather than uploading it a second time.
		if (batch) {
			step = 2;
			return;
		}
		uploadMut.mutate();
	}
</script>

<svelte:head><title>Import clients · Contractor CRM</title></svelte:head>

<div class="import-page">
	<header class="import-page__head">
		<p class="import-page__eyebrow">Onboarding</p>
		<h1>Import clients</h1>
		<p class="import-page__lede">
			Bring an existing client list in from a spreadsheet — matched to your fields, checked for
			duplicates, and safe to run twice.
		</p>
	</header>

	<ImportStepper current={step} />

	{#if step === 1}
		<ImportUploadStep
			{file}
			bind:matchAction
			errorMessage={uploadError}
			loading={uploadMut.isPending}
			{onFile}
			{onContinue}
		/>
	{:else if step === 2 && batch}
		<ImportMapStep
			headers={batch.headers}
			previewRows={batch.preview_rows}
			bind:mapping
			errorMessage={mapError}
			loading={mapReviewMut.isPending}
			onBack={() => (step = 1)}
			onReview={() => mapReviewMut.mutate()}
		/>
	{:else if step === 3 && batch && summary}
		<ImportReviewStep
			{summary}
			rowCount={batch.row_count}
			errorMessage={reviewError}
			loading={commitMut.isPending}
			onBack={() => (step = 2)}
			onCommit={() => commitMut.mutate()}
		/>
	{:else if step === 4 && batch && commitResult}
		<ImportDoneStep
			batchId={batch.batch_id}
			sourceFilename={file?.name ?? 'Your file'}
			initialStatus={commitResult.status}
			initialCounts={commitResult.counts}
			{clientsHref}
		/>
	{/if}
</div>

<style lang="scss">
	.import-page {
		max-width: 1040px;
		margin-inline: auto;
		padding-block: var(--space-large);
		padding-inline: var(--space-base);

		&__head {
			margin-bottom: var(--space-large);
		}
		&__eyebrow {
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;
			color: var(--color-interactive);
			margin: 0;
		}
		h1 {
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-largest);
			font-weight: 600;
			color: var(--color-heading);
			margin: var(--space-smaller) 0 0;
		}
		&__lede {
			margin: var(--space-small) 0 0;
			color: var(--color-text--secondary);
			max-width: 60ch;
		}
	}
</style>
