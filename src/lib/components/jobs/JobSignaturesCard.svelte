<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CollectJobSignatureDialog from '$lib/components/jobs/CollectJobSignatureDialog.svelte';
	import {
		collectJobSignature,
		fetchJobSignatureDocument,
		fetchJobSignatures,
		jobSignatureDocumentKey,
		jobSignaturesKey,
		type JobSignatureRow
	} from '$lib/signatures/api';
	import type { JobSignatureType } from '$lib/signatures/types';
	import type { JobLineItem, JobVisit } from '$lib/jobs/api';
	import { jobEventsKey } from '$lib/jobs/api';
	import signatureIcon from '@tabler/icons/outline/signature.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The job's collected sign-offs, newest first. A signature is never edited, voided or deleted — that is
	// the whole point of it — so this card only ever adds. When the job has moved on since one was signed,
	// the row says so and offers a fresh one, which is Housecall Pro's grey-turns-red made into words.

	let {
		jobId,
		lines,
		visits,
		totalMinor,
		currencyCode,
		locale,
		clientName,
		canRecord,
		active
	}: {
		jobId: string;
		lines: JobLineItem[];
		visits: JobVisit[];
		/** Null when this person may not see the job's prices. */
		totalMinor: number | null;
		currencyCode: string;
		locale: string;
		clientName: string | null;
		canRecord: boolean;
		active: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let collecting = $state(false);
	let saving = $state(false);
	let openSignature = $state<JobSignatureRow | null>(null);

	const signaturesQuery = createQuery(() => ({
		queryKey: jobSignaturesKey(jobId),
		queryFn: () => fetchJobSignatures(jobId),
		enabled: Boolean(jobId)
	}));

	// The signed document is revealed content: it stays off until a row is opened. Hovering a row warms it,
	// so the click usually lands on a cached answer.
	const documentQuery = createQuery(() => ({
		queryKey: jobSignatureDocumentKey(openSignature?.id ?? ''),
		queryFn: () => fetchJobSignatureDocument(jobId, openSignature!.id),
		enabled: Boolean(openSignature),
		// A frozen document cannot change, so once it is read there is never a reason to read it again.
		staleTime: Infinity
	}));

	const signatures = $derived(signaturesQuery.data?.signatures ?? []);
	const canCollect = $derived(Boolean(signaturesQuery.data?.can_collect) && canRecord && active);

	const TYPE_LABELS: Record<JobSignatureType, string> = {
		work_authorization: 'Work authorization',
		work_completion: 'Work completion',
		other: 'Signature'
	};

	const dateTimeFormat = $derived(
		new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeStyle: 'short' })
	);
	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric' })
	);

	function warmDocument(signature: JobSignatureRow) {
		void queryClient.prefetchQuery({
			queryKey: jobSignatureDocumentKey(signature.id),
			queryFn: () => fetchJobSignatureDocument(jobId, signature.id),
			staleTime: Infinity
		});
	}

	async function collect(input: {
		signature_type: JobSignatureType;
		signer_name: string;
		signer_role: string | null;
		statement: string;
		method: 'typed' | 'drawn';
		image?: string;
		visit_id: string | null;
	}) {
		saving = true;
		try {
			await collectJobSignature(jobId, input);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: jobSignaturesKey(jobId) }),
				queryClient.invalidateQueries({ queryKey: jobEventsKey(jobId) })
			]);
			toast.success('Signature saved.');
		} finally {
			saving = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RailCard title="Signatures" icon={signatureIcon} count={signatures.length || undefined}>
	{#snippet actions()}
		{#if canCollect}
			<Button size="small" variant="tertiary" onclick={() => (collecting = true)}>
				Collect signature
			</Button>
		{/if}
	{/snippet}

	{#if signaturesQuery.isPending}
		<LoadingSkeleton variant="text" rows={2} label="Loading signatures" />
	{:else if signaturesQuery.isError}
		<p class="job-signatures__error" role="alert">Signatures could not be loaded.</p>
	{:else if signatures.length === 0}
		<EmptyState
			icon={signatureIcon}
			title="No signatures yet"
			description={canCollect
				? 'Have the customer sign to authorize the work, or to confirm it is finished.'
				: 'Nobody has signed off on this job.'}
		/>
	{:else}
		<ul class="job-signatures__list">
			{#each signatures as signature (signature.id)}
				<li>
					<button
						type="button"
						class="job-signatures__row"
						onmouseenter={() => warmDocument(signature)}
						onfocus={() => warmDocument(signature)}
						onclick={() => (openSignature = signature)}
					>
						<span class="job-signatures__type">{TYPE_LABELS[signature.signature_type]}</span>
						<span class="job-signatures__signer">
							{signature.signer_name}{signature.signer_role ? ` · ${signature.signer_role}` : ''}
						</span>
						<span class="job-signatures__meta">
							{dateTimeFormat.format(new Date(signature.collected_at))}
							{#if signature.collected_by_name}
								· collected by {signature.collected_by_name}
							{/if}
						</span>
						{#if signature.is_stale}
							<span class="job-signatures__stale">
								<span class="job-signatures__stale-icon" aria-hidden="true">{@html alertIcon}</span>
								The job has changed since this was signed
							</span>
						{/if}
					</button>
				</li>
			{/each}
		</ul>

		{#if canCollect && signatures.some((signature) => signature.is_stale)}
			<Button size="small" variant="secondary" onclick={() => (collecting = true)}>
				Collect a new signature
			</Button>
		{/if}
	{/if}
</RailCard>

{#if collecting}
	<CollectJobSignatureDialog
		open
		{clientName}
		{lines}
		{visits}
		{totalMinor}
		{currencyCode}
		{locale}
		{saving}
		onClose={() => (collecting = false)}
		onCollect={collect}
	/>
{/if}

<Dialog
	open={openSignature !== null}
	title="Signed document"
	onClose={() => (openSignature = null)}
>
	{#if openSignature}
		<div class="signed-document">
			<p class="signed-document__statement">“{openSignature.statement}”</p>

			{#if documentQuery.isPending}
				<LoadingSkeleton variant="text" rows={4} label="Loading the signed document" />
			{:else if documentQuery.isError}
				<p class="job-signatures__error" role="alert">That signed document could not be loaded.</p>
			{:else if documentQuery.data}
				{@const frozen = documentQuery.data.document}
				<section class="signed-document__block">
					<h3 class="signed-document__block-title">The job as it was signed</h3>
					<p class="signed-document__job">
						Job #{frozen.job_number}{frozen.title ? ` · ${frozen.title}` : ''}
					</p>
					{#if frozen.client.display_name}
						<p class="signed-document__line-muted">{frozen.client.display_name}</p>
					{/if}
					{#if frozen.property.address_line1}
						<p class="signed-document__line-muted">
							{frozen.property.address_line1}{frozen.property.city
								? `, ${frozen.property.city}`
								: ''}
						</p>
					{/if}
					<ul class="signed-document__lines">
						{#each frozen.lines as line (line.line_id)}
							<li class="signed-document__line">
								<span>
									{line.name}
									{#if line.quantity !== 1}
										<span class="signed-document__quantity">
											× {line.quantity}{line.unit_label ? ` ${line.unit_label}` : ''}
										</span>
									{/if}
								</span>
								{#if line.line_total_minor !== undefined}
									<span class="signed-document__amount">
										{money.format(line.line_total_minor / 100)}
									</span>
								{/if}
							</li>
						{/each}
					</ul>
					{#if frozen.totals}
						<p class="signed-document__total">
							<span>Total signed for</span>
							<span>{money.format(frozen.totals.total_minor / 100)}</span>
						</p>
					{/if}
				</section>

				<section class="signed-document__block">
					<h3 class="signed-document__block-title">Signed by</h3>
					{#if openSignature.has_image}
						<img
							class="signed-document__image"
							src={`/api/jobs/${jobId}/signatures/${openSignature.id}/image`}
							alt={`${openSignature.signer_name}'s signature`}
						/>
					{:else}
						<p class="signed-document__typed">{openSignature.signer_name}</p>
					{/if}
					<p class="signed-document__line-muted">
						{openSignature.signer_name}{openSignature.signer_role
							? ` · ${openSignature.signer_role}`
							: ''}
					</p>
					<p class="signed-document__line-muted">
						{dateTimeFormat.format(new Date(openSignature.collected_at))}
						{#if openSignature.visit_date}
							· on the {dateFormat.format(new Date(`${openSignature.visit_date}T00:00:00`))} visit
						{/if}
					</p>
				</section>

				{#if openSignature.is_stale}
					<p class="signed-document__stale" role="status">
						The job has changed since this was signed. What you see above is what was actually
						agreed to — collect a new signature for the job as it stands now.
					</p>
				{/if}
			{/if}

			<footer class="signed-document__actions">
				<Button variant="secondary" variation="subtle" onclick={() => (openSignature = null)}>
					Close
				</Button>
			</footer>
		</div>
	{/if}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-signatures {
		&__list {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: grid;
			gap: var(--space-smaller);
			width: 100%;
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			text-align: left;
			cursor: pointer;

			&:hover,
			&:focus-visible {
				border-color: var(--color-border--interactive);
			}
		}

		&__type {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__signer {
			color: var(--color-text);
		}

		&__meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__stale {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__stale-icon :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
		}
	}

	.signed-document {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__statement {
			margin: 0;
			color: var(--color-text);
			font-style: italic;
		}

		&__block {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__block-title {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}

		&__job {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__line-muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__lines {
			display: grid;
			gap: var(--space-smaller);
			margin: var(--space-smaller) 0 0;
			padding: 0;
			list-style: none;
		}

		&__line {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__quantity {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__amount {
			flex: 0 0 auto;
			font-variant-numeric: tabular-nums;
		}

		&__total {
			display: flex;
			justify-content: space-between;
			gap: var(--space-small);
			margin: 0;
			padding-top: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}

		// Paper, like the pad it was drawn on: the ink is a fixed dark colour, so it must keep its own
		// background in both themes.
		&__image {
			width: 100%;
			max-width: 320px;
			height: auto;
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: #ffffff;
		}

		&__typed {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-family: 'Segoe Script', 'Brush Script MT', cursive;
		}

		&__stale {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
		}
	}
</style>
