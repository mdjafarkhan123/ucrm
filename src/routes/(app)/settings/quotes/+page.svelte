<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import QuoteTermsEditor from '$lib/components/settings/QuoteTermsEditor.svelte';
	import RepresentativeSignatureInput, {
		type PendingSignature
	} from '$lib/components/settings/RepresentativeSignatureInput.svelte';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		fetchSettingsQuotes,
		settingsQuotesKey,
		saveQuoteTerms,
		saveQuoteRepresentative,
		uploadQuoteRepresentativeSignature,
		saveQuoteTargetMargin,
		saveQuoteSignaturePolicy,
		isSaveConflict,
		type SettingsQuotes
	} from '$lib/settings/api';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import signatureIcon from '@tabler/icons/outline/signature.svg?raw';
	import percentageIcon from '@tabler/icons/outline/percentage.svg?raw';
	import writingSignIcon from '@tabler/icons/outline/writing-sign.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsQuotesKey,
		queryFn: fetchSettingsQuotes
	}));

	type Conflict = { editor_name: string | null; edited_at: string | null };

	function patchCache(patch: (current: SettingsQuotes) => SettingsQuotes) {
		queryClient.setQueryData(settingsQuotesKey, (current: SettingsQuotes | undefined) =>
			current ? patch(current) : current
		);
	}

	// --- Terms ------------------------------------------------------------------------------------------

	let termsDraft = $state<string | null>(null);
	let termsSaved = $state<string | null>(null);
	let termsSaving = $state(false);
	let termsError = $state('');
	let termsConflict = $state<Conflict | null>(null);

	$effect(() => {
		const terms = query.data?.terms;
		if (!terms) return;
		untrack(() => {
			if (termsDraft !== null) return;
			termsDraft = terms.terms ?? '';
			termsSaved = terms.terms ?? '';
		});
	});

	const termsDirty = $derived(
		termsDraft !== null && termsSaved !== null && termsDraft !== termsSaved
	);

	function cancelTerms() {
		termsDraft = termsSaved;
		termsConflict = null;
		termsError = '';
	}

	async function saveTerms() {
		if (!query.data || termsDraft === null) return;
		termsSaving = true;
		termsError = '';
		termsConflict = null;

		const result = await saveQuoteTerms({
			expected_revision: query.data.terms.revision,
			terms: termsDraft
		}).catch((error: Error) => {
			termsError = error.message;
			return null;
		});

		termsSaving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			termsConflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			return;
		}

		termsSaved = result.quote_terms ?? '';
		termsDraft = termsSaved;
		toast.success('Terms saved.');
		patchCache((current) => ({
			...current,
			terms: { ...current.terms, terms: result.quote_terms, revision: result.quote_terms_revision }
		}));
		await queryClient.invalidateQueries({ queryKey: settingsQuotesKey });
	}

	// --- Representative -----------------------------------------------------------------------------------

	let repEnabled = $state<boolean | null>(null);
	let repName = $state('');
	let repTitle = $state('');
	let repSavedEnabled = $state<boolean | null>(null);
	let repSavedName = $state('');
	let repSavedTitle = $state('');
	let repPending = $state<PendingSignature>({ kind: 'none' });
	let repSaving = $state(false);
	let repError = $state('');
	let repFieldErrors = $state<Record<string, string>>({});
	let repConflict = $state<Conflict | null>(null);

	$effect(() => {
		const rep = query.data?.representative;
		if (!rep) return;
		untrack(() => {
			if (repEnabled !== null) return;
			repEnabled = rep.enabled;
			repName = rep.name ?? '';
			repTitle = rep.title ?? '';
			repSavedEnabled = rep.enabled;
			repSavedName = rep.name ?? '';
			repSavedTitle = rep.title ?? '';
		});
	});

	const repDirty = $derived(
		repEnabled !== null &&
			(repEnabled !== repSavedEnabled ||
				repName !== repSavedName ||
				repTitle !== repSavedTitle ||
				repPending.kind !== 'none')
	);

	function cancelRep() {
		repEnabled = repSavedEnabled;
		repName = repSavedName;
		repTitle = repSavedTitle;
		repPending = { kind: 'none' };
		repConflict = null;
		repError = '';
		repFieldErrors = {};
	}

	async function saveRep() {
		if (!query.data || repEnabled === null) return;
		if (repEnabled && !repName.trim()) {
			repFieldErrors = { name: 'Enter a representative name.' };
			return;
		}

		repSaving = true;
		repError = '';
		repFieldErrors = {};
		repConflict = null;

		let signatureFields: {
			signature_object_key?: string;
			signature_image?: string;
			remove_signature?: boolean;
		} = {};
		try {
			if (repPending.kind === 'upload') {
				const uploaded = await uploadQuoteRepresentativeSignature(repPending.file);
				signatureFields = { signature_object_key: uploaded.object_key };
			} else if (repPending.kind === 'drawn') {
				signatureFields = { signature_image: repPending.dataUrl };
			} else if (repPending.kind === 'remove') {
				signatureFields = { remove_signature: true };
			}
		} catch (cause) {
			repError = cause instanceof Error ? cause.message : 'That signature could not be uploaded.';
			repSaving = false;
			return;
		}

		const result = await saveQuoteRepresentative({
			expected_revision: query.data.representative.revision,
			enabled: repEnabled,
			name: repName.trim(),
			title: repTitle.trim(),
			...signatureFields
		}).catch((error: Error) => {
			repError = error.message;
			return null;
		});

		repSaving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			repConflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			return;
		}

		repSavedEnabled = result.enabled;
		repSavedName = result.name ?? '';
		repSavedTitle = result.title ?? '';
		repEnabled = repSavedEnabled;
		repName = repSavedName;
		repTitle = repSavedTitle;
		repPending = { kind: 'none' };
		toast.success('Representative saved.');
		patchCache((current) => ({
			...current,
			representative: {
				...current.representative,
				enabled: result.enabled,
				name: result.name,
				title: result.title,
				signature_url: result.signature_url,
				revision: result.revision
			}
		}));
		await queryClient.invalidateQueries({ queryKey: settingsQuotesKey });
	}

	// --- Target margin ------------------------------------------------------------------------------------

	function marginToText(basisPoints: number | undefined | null) {
		return basisPoints === undefined || basisPoints === null ? '' : (basisPoints / 100).toString();
	}

	let marginDraft = $state<string | null>(null);
	let marginSaved = $state<string | null>(null);
	let marginSaving = $state(false);
	let marginError = $state('');
	let marginConflict = $state<Conflict | null>(null);

	$effect(() => {
		const margin = query.data?.target_margin;
		if (!margin) return;
		untrack(() => {
			if (marginDraft !== null) return;
			marginDraft = marginToText(margin.basis_points);
			marginSaved = marginDraft;
		});
	});

	const marginDirty = $derived(
		marginDraft !== null && marginSaved !== null && marginDraft !== marginSaved
	);

	function cancelMargin() {
		marginDraft = marginSaved;
		marginConflict = null;
		marginError = '';
	}

	async function saveMargin() {
		if (!query.data || marginDraft === null) return;
		const trimmed = marginDraft.trim();
		let basisPoints: number | null = null;
		if (trimmed) {
			const parsed = Number(trimmed);
			if (!Number.isFinite(parsed) || parsed <= 0 || parsed >= 100) {
				marginError = 'Target margin must be greater than 0% and below 100%.';
				return;
			}
			basisPoints = Math.round(parsed * 100);
		}

		marginSaving = true;
		marginError = '';
		marginConflict = null;

		const result = await saveQuoteTargetMargin({
			expected_revision: query.data.target_margin.revision,
			margin_basis_points: basisPoints
		}).catch((error: Error) => {
			marginError = error.message;
			return null;
		});

		marginSaving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			marginConflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			return;
		}

		marginSaved = marginToText(result.quote_target_margin_basis_points);
		marginDraft = marginSaved;
		toast.success('Target margin saved.');
		patchCache((current) => ({
			...current,
			target_margin: {
				...current.target_margin,
				basis_points: result.quote_target_margin_basis_points ?? undefined,
				revision: result.quote_target_margin_revision
			}
		}));
		await queryClient.invalidateQueries({ queryKey: settingsQuotesKey });
	}

	// --- Signature policy -----------------------------------------------------------------------------------

	let sigRequired = $state<boolean | null>(null);
	let sigSaved = $state<boolean | null>(null);
	let sigSaving = $state(false);
	let sigError = $state('');
	let sigConflict = $state<Conflict | null>(null);

	$effect(() => {
		const policy = query.data?.signature_policy;
		if (!policy) return;
		untrack(() => {
			if (sigRequired !== null) return;
			sigRequired = policy.require_customer_signature;
			sigSaved = policy.require_customer_signature;
		});
	});

	const sigDirty = $derived(sigRequired !== null && sigSaved !== null && sigRequired !== sigSaved);

	function cancelSig() {
		sigRequired = sigSaved;
		sigConflict = null;
		sigError = '';
	}

	async function saveSig() {
		if (!query.data || sigRequired === null) return;
		sigSaving = true;
		sigError = '';
		sigConflict = null;

		const result = await saveQuoteSignaturePolicy({
			expected_revision: query.data.signature_policy.revision,
			require_customer_signature: sigRequired
		}).catch((error: Error) => {
			sigError = error.message;
			return null;
		});

		sigSaving = false;
		if (!result) return;
		if (isSaveConflict(result)) {
			sigConflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			return;
		}

		sigSaved = result.quote_require_customer_signature;
		sigRequired = sigSaved;
		toast.success('Signature policy saved.');
		patchCache((current) => ({
			...current,
			signature_policy: {
				...current.signature_policy,
				require_customer_signature: result.quote_require_customer_signature,
				revision: result.quote_signature_policy_revision
			}
		}));
		await queryClient.invalidateQueries({ queryKey: settingsQuotesKey });
	}
</script>

<svelte:head><title>Quote Settings · Settings · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet lastEditorNote(editor: { name: string | null; at: string | null } | null)}
	{#if editor}
		<p class="quote-settings__note">
			Last changed by {editor.name ?? 'a teammate'}
			{#if editor.at}
				· <span title={exactTime(editor.at)}>{relativeTime(editor.at)}</span>
			{/if}
		</p>
	{/if}
{/snippet}

{#snippet conflictBanner(conflict: Conflict | null)}
	{#if conflict}
		<p class="quote-settings__conflict" role="alert">
			<span aria-hidden="true">{@html alertTriangleIcon}</span>
			{conflict.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version
			before saving yours.
		</p>
	{/if}
{/snippet}

<PageContainer variant="fill">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Quote Settings' }]}
	/>

	<PageHeader
		eyebrow="Business"
		title="Quote Settings"
		description="What every new quote starts with: your terms, who it's from, your private margin target, and whether a customer must sign."
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={4} />
	{:else if query.isError}
		<ErrorState description="Quote Settings could not be loaded." retry={() => query.refetch()} />
	{:else}
		{@const quotes = query.data}

		<div class="quote-settings">
			<SectionBlock
				title="Terms & conditions"
				hint="Copied into every new quote draft. Changing this never rewrites an existing draft or a quote already sent."
				icon={fileTextIcon}
				level={2}
			>
				{@render conflictBanner(termsConflict)}
				{#if termsError}<p class="quote-settings__error" role="alert">{termsError}</p>{/if}
				{@render lastEditorNote(quotes.terms.last_editor)}

				{#if termsDraft !== null}
					<QuoteTermsEditor id="quote-terms" bind:value={termsDraft} disabled={termsSaving} />
				{/if}

				<div class="quote-settings__actions">
					<Button
						variant="secondary"
						size="small"
						disabled={!termsDirty || termsSaving}
						onclick={cancelTerms}>Cancel</Button
					>
					<Button
						size="small"
						disabled={!termsDirty || termsSaving}
						loading={termsSaving}
						onclick={() => void saveTerms()}>Save</Button
					>
				</div>
			</SectionBlock>

			<SectionBlock
				title="Representative"
				hint="Who a quote is from. Presentation only — this never becomes an approval workflow. Copied into every new quote draft."
				icon={signatureIcon}
				level={2}
			>
				{@render conflictBanner(repConflict)}
				{#if repError}<p class="quote-settings__error" role="alert">{repError}</p>{/if}
				{@render lastEditorNote(quotes.representative.last_editor)}

				{#if repEnabled !== null}
					<Toggle
						id="rep-enabled"
						label="Show a representative on quotes"
						description="When off, a quote shows no name, title, or signature block."
						labelSide="start"
						bind:checked={repEnabled}
						disabled={repSaving}
					/>

					{#if repEnabled}
						<div class="quote-settings__row">
							<Input
								id="rep-name"
								label="Name"
								required
								bind:value={repName}
								disabled={repSaving}
								invalid={Boolean(repFieldErrors.name)}
								errorMessage={repFieldErrors.name ?? ''}
							/>
							<Input id="rep-title" label="Title" bind:value={repTitle} disabled={repSaving} />
						</div>

						<RepresentativeSignatureInput
							idPrefix="rep"
							currentUrl={quotes.representative.signature_url}
							disabled={repSaving}
							bind:pending={repPending}
						/>
					{/if}
				{/if}

				<div class="quote-settings__actions">
					<Button
						variant="secondary"
						size="small"
						disabled={!repDirty || repSaving}
						onclick={cancelRep}>Cancel</Button
					>
					<Button
						size="small"
						disabled={!repDirty || repSaving}
						loading={repSaving}
						onclick={() => void saveRep()}>Save</Button
					>
				</div>
			</SectionBlock>

			{#if quotes.permissions.view_cost}
				<SectionBlock
					title="Target margin"
					hint="Private guidance only, never shown to a customer and never enforced automatically."
					icon={percentageIcon}
					level={2}
				>
					{@render conflictBanner(marginConflict)}
					{#if marginError}<p class="quote-settings__error" role="alert">{marginError}</p>{/if}
					{@render lastEditorNote(quotes.target_margin.last_editor)}

					{#if marginDraft !== null}
						<Input
							id="target-margin"
							label="Target margin %"
							size="small"
							inputmode="decimal"
							placeholder="Not set"
							bind:value={marginDraft}
							disabled={marginSaving}
						/>
					{/if}

					<div class="quote-settings__actions">
						<Button
							variant="secondary"
							size="small"
							disabled={!marginDirty || marginSaving}
							onclick={cancelMargin}>Cancel</Button
						>
						<Button
							size="small"
							disabled={!marginDirty || marginSaving}
							loading={marginSaving}
							onclick={() => void saveMargin()}>Save</Button
						>
					</div>
				</SectionBlock>
			{/if}

			<SectionBlock
				title="Signature policy"
				hint="Copied into each new quote and frozen at publish. Changing this never changes a link already sent — republish to apply a newer policy."
				icon={writingSignIcon}
				level={2}
			>
				{@render conflictBanner(sigConflict)}
				{#if sigError}<p class="quote-settings__error" role="alert">{sigError}</p>{/if}
				{@render lastEditorNote(quotes.signature_policy.last_editor)}

				{#if sigRequired !== null}
					<Toggle
						id="sig-required"
						label="Require the customer to sign before a quote counts as accepted"
						labelSide="start"
						bind:checked={sigRequired}
						disabled={sigSaving}
					/>
				{/if}

				<div class="quote-settings__actions">
					<Button
						variant="secondary"
						size="small"
						disabled={!sigDirty || sigSaving}
						onclick={cancelSig}>Cancel</Button
					>
					<Button
						size="small"
						disabled={!sigDirty || sigSaving}
						loading={sigSaving}
						onclick={() => void saveSig()}>Save</Button
					>
				</div>
			</SectionBlock>
		</div>
	{/if}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.quote-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__row {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__conflict {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 18px;
				height: 18px;
				flex: 0 0 auto;
			}
		}

		&__error {
			margin: 0;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.quote-settings__row {
			grid-template-columns: 1fr;
		}
	}
</style>
