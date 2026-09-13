<script lang="ts">
	import { resolve } from '$app/paths';
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import ImportStepper from '$lib/components/imports/ImportStepper.svelte';
	import ImportUploadStep from '$lib/components/imports/ImportUploadStep.svelte';
	import ImportMapStep from '$lib/components/imports/ImportMapStep.svelte';
	import ImportReviewStep from '$lib/components/imports/ImportReviewStep.svelte';
	import PriceBookImportDoneStep from '$lib/components/imports/PriceBookImportDoneStep.svelte';
	import { ImportError } from '$lib/imports/api';
	import {
		autoMapCatalogHeaders,
		commitCatalogImport,
		IMPORT_CATALOG_FIELD_OPTIONS,
		reviewCatalogImport,
		uploadCatalogImport,
		type CatalogColumnMapping,
		type CatalogCommitResult,
		type CatalogMatchAction,
		type CatalogReviewSummary,
		type CatalogUploadResult
	} from '$lib/imports/catalog-api';

	// Onboarding & Data Portability, Part 3: the Price Book import wizard. Same four steps as Client import,
	// but stateless -- there is no batch id. Upload parses the CSV; the browser then holds the rows and sends
	// them, with the mapping, to Review and again to Commit, which writes everything in one request and
	// returns the final result immediately (no polling, no background worker).
	const queryClient = useQueryClient();
	const priceBookHref = resolve('/(app)/settings/price-book');

	let step = $state(1);
	let matchAction = $state<CatalogMatchAction>('update');
	let file = $state<File | null>(null);
	let upload = $state<CatalogUploadResult | null>(null);
	let mapping = $state<CatalogColumnMapping>({});
	let summary = $state<CatalogReviewSummary | null>(null);
	let commitResult = $state<CatalogCommitResult | null>(null);

	let uploadError = $state('');
	let mapError = $state('');
	let reviewError = $state('');

	function messageFrom(error: unknown, fallback: string): string {
		if (error instanceof ImportError) {
			return Object.values(error.fieldErrors)[0] ?? error.message ?? fallback;
		}
		return fallback;
	}

	const uploadMut = createMutation(() => ({
		mutationFn: () => {
			if (!file) throw new Error('Choose a CSV file to import.');
			return uploadCatalogImport(file);
		},
		onSuccess: (result) => {
			upload = result;
			mapping = autoMapCatalogHeaders(result.headers);
			uploadError = '';
			step = 2;
		},
		onError: (error) => {
			uploadError = messageFrom(error, 'That file could not be uploaded.');
		}
	}));

	const reviewMut = createMutation(() => ({
		mutationFn: () => {
			if (!upload) throw new Error('Upload a file first.');
			return reviewCatalogImport({
				rows: upload.rows,
				column_mapping: mapping,
				match_action: matchAction
			});
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
			if (!upload) throw new Error('Upload a file first.');
			return commitCatalogImport({
				rows: upload.rows,
				column_mapping: mapping,
				match_action: matchAction
			});
		},
		onSuccess: (result) => {
			commitResult = result;
			reviewError = '';
			void queryClient.invalidateQueries({ queryKey: ['catalog-items'] });
			step = 4;
		},
		onError: (error) => {
			reviewError = messageFrom(error, 'That import could not be started.');
		}
	}));

	function onFile(next: File | null) {
		file = next;
		upload = null;
		summary = null;
		uploadError = '';
	}

	function onContinue() {
		if (upload) {
			step = 2;
			return;
		}
		uploadMut.mutate();
	}

	const catalogMatchOptions = [
		{ value: 'update', label: 'Add new items and update the ones I already have' },
		{ value: 'skip', label: 'Add new items only — leave my existing ones untouched' }
	];

	function attentionNote(count: number): string {
		return `${count} ${count === 1 ? 'row needs' : 'rows need'} a fix, or repeats a name already in this file. ${count === 1 ? 'It' : 'They'} won't be imported, and you'll get a list to download once you import.`;
	}
</script>

<svelte:head><title>Import Price Book · Contractor CRM</title></svelte:head>

<div class="import-page">
	<header class="import-page__head">
		<p class="import-page__eyebrow">Onboarding</p>
		<h1>Import Price Book</h1>
		<p class="import-page__lede">
			Bring your products and services in from a spreadsheet — matched by name, checked for
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
			title="Upload your Price Book"
			subtitle="A spreadsheet saved as CSV, with one product or service per row."
			matchActionLabel="How should we handle items you already have?"
			matchHint="We recognise an existing item by its name."
			matchOptions={catalogMatchOptions}
			sampleHref="/samples/price-book-import-sample.csv"
			{onFile}
			{onContinue}
		/>
	{:else if step === 2 && upload}
		<ImportMapStep
			headers={upload.headers}
			previewRows={upload.rows.slice(0, 20)}
			bind:mapping
			errorMessage={mapError}
			loading={reviewMut.isPending}
			fieldOptions={IMPORT_CATALOG_FIELD_OPTIONS}
			onBack={() => (step = 1)}
			onReview={() => reviewMut.mutate()}
		/>
	{:else if step === 3 && upload && summary}
		<ImportReviewStep
			{summary}
			rowCount={upload.row_count}
			errorMessage={reviewError}
			loading={commitMut.isPending}
			newLabel="New items"
			itemLabel="items"
			{attentionNote}
			safetyNote="Importing only adds items to your Price Book — nothing is sent to anyone, and no quotes or jobs are affected."
			onBack={() => (step = 2)}
			onCommit={() => commitMut.mutate()}
		/>
	{:else if step === 4 && commitResult}
		<PriceBookImportDoneStep
			sourceFilename={file?.name ?? 'Your file'}
			counts={commitResult.counts}
			errorRows={commitResult.error_rows}
			{priceBookHref}
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
