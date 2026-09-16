<script lang="ts">
	import { resolve } from '$app/paths';
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import ImportStepper from '$lib/components/imports/ImportStepper.svelte';
	import ImportUploadStep from '$lib/components/imports/ImportUploadStep.svelte';
	import ImportMapStep from '$lib/components/imports/ImportMapStep.svelte';
	import ImportReviewStep from '$lib/components/imports/ImportReviewStep.svelte';
	import OpeningBalanceDoneStep from '$lib/components/imports/OpeningBalanceDoneStep.svelte';
	import type { MatchAction } from '$lib/imports/api';
	import {
		autoMapOpeningBalanceHeaders,
		commitOpeningBalanceImport,
		ImportError,
		OPENING_BALANCE_FIELD_OPTIONS,
		reviewOpeningBalanceImport,
		setOpeningBalanceImportMapping,
		uploadOpeningBalanceImport,
		type OpeningBalanceColumnMapping,
		type ImportCounts,
		type ImportStatus,
		type ReviewSummary,
		type UploadResult
	} from '$lib/imports/opening-balance-api';

	const queryClient = useQueryClient();
	const clientsHref = resolve('/(app)/clients');

	let step = $state(1);
	// No skip/update choice for this import (a match is always a correction) -- ImportUploadStep is shared
	// with the client importer, so this stays bound but unused with showMatchAction={false}.
	let matchAction = $state<MatchAction>('update');
	let file = $state<File | null>(null);
	let batch = $state<UploadResult | null>(null);
	let mapping = $state<OpeningBalanceColumnMapping>({});
	let summary = $state<ReviewSummary | null>(null);
	let commitResult = $state<{ status: ImportStatus; counts: ImportCounts } | null>(null);

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
			return uploadOpeningBalanceImport(file);
		},
		onSuccess: (result) => {
			batch = result;
			mapping = autoMapOpeningBalanceHeaders(result.headers);
			uploadError = '';
			step = 2;
		},
		onError: (error) => {
			uploadError = messageFrom(error, 'That file could not be uploaded.');
		}
	}));

	const mapReviewMut = createMutation(() => ({
		mutationFn: async () => {
			if (!batch) throw new Error('Upload a file first.');
			await setOpeningBalanceImportMapping(batch.batch_id, { column_mapping: mapping });
			return reviewOpeningBalanceImport(batch.batch_id);
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
			return commitOpeningBalanceImport(batch.batch_id);
		},
		onSuccess: (result) => {
			commitResult = { status: result.status, counts: result.counts };
			reviewError = '';
			// A freshly recorded opening balance changes what every affected client's balance shows.
			void queryClient.invalidateQueries({ queryKey: ['clients'] });
			step = 4;
		},
		onError: (error) => {
			reviewError = messageFrom(error, 'That import could not be started.');
		}
	}));

	function onFile(next: File | null) {
		file = next;
		batch = null;
		summary = null;
		uploadError = '';
	}

	function onContinue() {
		if (batch) {
			step = 2;
			return;
		}
		uploadMut.mutate();
	}
</script>

<svelte:head><title>Import opening balances · Contractor CRM</title></svelte:head>

<div class="import-page">
	<header class="import-page__head">
		<p class="import-page__eyebrow">Financial</p>
		<h1>Import opening balances</h1>
		<p class="import-page__lede">
			Record what a client already owed you, or a credit they already had, from before you started
			using this CRM — one receivable or credit fact per client, as of a date you choose.
		</p>
	</header>

	<ImportStepper current={step} />

	{#if step === 1}
		<ImportUploadStep
			{file}
			bind:matchAction
			showMatchAction={false}
			title="Upload your opening balances"
			subtitle="A spreadsheet saved as CSV, with one balance per row. Only clients already in your CRM can carry an opening balance."
			sampleHref="/samples/opening-balance-import-sample.csv"
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
			fieldOptions={OPENING_BALANCE_FIELD_OPTIONS}
			showOverwriteToggle={false}
			errorMessage={mapError}
			loading={mapReviewMut.isPending}
			onBack={() => (step = 1)}
			onReview={() => mapReviewMut.mutate()}
		/>
	{:else if step === 3 && batch && summary}
		<ImportReviewStep
			{summary}
			rowCount={batch.row_count}
			newLabel="New balances"
			itemLabel="opening balances"
			attentionNote={(n) =>
				`${n} ${n === 1 ? 'row needs' : 'rows need'} a fix — an email that doesn't match a client, an invalid amount or date, or two rows setting the same client's balance at once. ${n === 1 ? 'It' : 'They'} won't be imported, and you'll get a file listing ${n === 1 ? 'it' : 'them'} to fix once the import finishes.`}
			safetyNote="Importing never emails or texts your clients, and never starts automations, reminders, or dunning."
			errorMessage={reviewError}
			loading={commitMut.isPending}
			onBack={() => (step = 2)}
			onCommit={() => commitMut.mutate()}
		/>
	{:else if step === 4 && batch && commitResult}
		<OpeningBalanceDoneStep
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
