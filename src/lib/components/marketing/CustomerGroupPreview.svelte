<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchGroupPreviewCounts,
		fetchGroupPreviewRecipients,
		type RecipientPreviewPage
	} from '$lib/marketing/api';
	import {
		completeGroupRules,
		marketingExclusionReasonLabels,
		marketingGroupPreviewKey,
		type MarketingExclusionReason,
		type MarketingGroupRules,
		type MarketingPreviewRecipient
	} from '$lib/marketing/customer-groups';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import mailCheckIcon from '@tabler/icons/outline/mail-check.svg?raw';
	import userMinusIcon from '@tabler/icons/outline/user-minus.svg?raw';

	// The exact recipient count for the rules currently in the builder, debounced so a run of edits asks
	// once, not on every keystroke. "View customers" reveals the bounded list on request (CLAUDE.md rule 10)
	// instead of loading it with every count refresh.
	let {
		rules,
		variant = 'section'
	}: {
		rules: MarketingGroupRules;
		/** `panel` is the customer group pop-up's tinted side column, beside the conditions it counts. */
		variant?: 'section' | 'panel';
	} = $props();

	// svelte-ignore state_referenced_locally
	let debouncedRules = $state(rules);
	$effect(() => {
		const snapshot = JSON.parse(JSON.stringify(rules)) as MarketingGroupRules;
		// A condition with nothing picked yet is left out, so the count keeps working while it's being filled.
		const handle = setTimeout(() => (debouncedRules = completeGroupRules(snapshot)), 400);
		return () => clearTimeout(handle);
	});

	const countsQuery = createQuery(() => ({
		queryKey: marketingGroupPreviewKey(debouncedRules),
		queryFn: () => fetchGroupPreviewCounts(debouncedRules),
		staleTime: 10_000
	}));
	const counts = $derived(countsQuery.data);
	const exclusionReasons = $derived(
		(
			Object.entries(counts?.excluded_by_reason ?? {}) as [MarketingExclusionReason, number][]
		).filter(([, count]) => count > 0)
	);

	let showRecipients = $state(false);
	let statusFilter = $state<'all' | 'eligible' | 'excluded'>('all');
	let pages = $state<MarketingPreviewRecipient[][]>([]);
	let loadingMore = $state(false);
	let listError = $state('');

	function pageCursor(): RecipientPreviewPage {
		const last = pages.at(-1)?.at(-1);
		return last
			? {
					status: statusFilter,
					after_display_name: last.display_name,
					after_client_id: last.client_id
				}
			: { status: statusFilter };
	}

	async function loadFirstPage() {
		listError = '';
		pages = [];
		loadingMore = true;
		try {
			const recipients = await fetchGroupPreviewRecipients(debouncedRules, {
				status: statusFilter
			});
			pages = [recipients];
		} catch (error) {
			listError =
				error instanceof Error ? error.message : 'The recipient list could not be loaded.';
		} finally {
			loadingMore = false;
		}
	}

	async function loadMore() {
		loadingMore = true;
		listError = '';
		try {
			const recipients = await fetchGroupPreviewRecipients(debouncedRules, pageCursor());
			pages = [...pages, recipients];
		} catch (error) {
			listError =
				error instanceof Error ? error.message : 'The recipient list could not be loaded.';
		} finally {
			loadingMore = false;
		}
	}

	function toggleRecipients() {
		showRecipients = !showRecipients;
		if (showRecipients) void loadFirstPage();
	}

	function onStatusChange(next: string) {
		statusFilter = next as 'all' | 'eligible' | 'excluded';
		void loadFirstPage();
	}

	const flatRecipients = $derived(pages.flat());
	const lastPage = $derived(pages.at(-1) ?? []);
	const hasMore = $derived(lastPage.length === 50);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet recipientList()}
	{#if showRecipients}
		<div class="group-preview__list">
			<Select
				id="group-preview-status"
				ariaLabel="Filter recipients"
				value={statusFilter}
				options={[
					{ value: 'all', label: 'All matches' },
					{ value: 'eligible', label: 'Eligible only' },
					{ value: 'excluded', label: 'Excluded only' }
				]}
				onchange={onStatusChange}
			/>

			{#if listError}
				<ErrorState description={listError} retry={loadFirstPage} />
			{:else if loadingMore && pages.length === 0}
				<LoadingSkeleton variant="table" rows={4} label="Loading customers" />
			{:else if flatRecipients.length === 0}
				<p class="group-preview__empty">No customers match this filter yet.</p>
			{:else}
				<ul class="group-preview__recipients">
					{#each flatRecipients as recipient (recipient.client_id)}
						<li>
							<span class="group-preview__recipient-name">{recipient.display_name}</span>
							<span class="group-preview__recipient-email">{recipient.email ?? 'No email'}</span>
							{#if recipient.excluded_reason}
								<span class="group-preview__recipient-reason">
									{marketingExclusionReasonLabels[recipient.excluded_reason]}
								</span>
							{/if}
						</li>
					{/each}
				</ul>
				{#if hasMore}
					<Button variant="tertiary" size="small" loading={loadingMore} onclick={loadMore}>
						Load more
					</Button>
				{/if}
			{/if}
		</div>
	{/if}
{/snippet}

{#if variant === 'panel'}
	<section class="group-preview group-preview--panel" aria-labelledby="group-preview-title">
		<header class="group-preview__panel-head">
			<IconTile icon={usersIcon} tone="growth" size={32} white />
			<div>
				<h3 id="group-preview-title">Recipients</h3>
				<p>Updates as you add or remove conditions.</p>
			</div>
		</header>

		{#if countsQuery.isPending}
			<div class="group-preview__card group-preview__card--counting">
				<LoadingSkeleton variant="text" rows={2} label="Counting matching customers" />
			</div>
		{:else if countsQuery.isError}
			<div class="group-preview__card">
				<ErrorState
					title="The count could not be checked"
					description="Something went wrong. Try again."
					retry={() => countsQuery.refetch()}
					size="small"
				/>
			</div>
		{:else if counts}
			<div class="group-preview__card">
				<div class="group-preview__eligible">
					<span class="group-preview__eligible-value">
						{counts.eligible}
						<span class="group-preview__eligible-icon" aria-hidden="true"
							>{@html mailCheckIcon}</span
						>
					</span>
					<span class="group-preview__eligible-label">Eligible to receive email</span>
				</div>
				<ul class="group-preview__figures">
					<li>
						<span class="group-preview__figure-icon" aria-hidden="true">{@html usersIcon}</span>
						<span class="group-preview__figure-label">Match the rules</span>
						<strong>{counts.matches}</strong>
					</li>
					<li>
						<span class="group-preview__figure-icon" aria-hidden="true">{@html userMinusIcon}</span>
						<span class="group-preview__figure-label">Excluded</span>
						<strong>{counts.excluded}</strong>
					</li>
					{#each exclusionReasons as [reason, count] (reason)}
						<li class="group-preview__figure-reason">
							<span class="group-preview__figure-label"
								>{marketingExclusionReasonLabels[reason]}</span
							>
							<strong>{count}</strong>
						</li>
					{/each}
				</ul>
			</div>

			<div class="group-preview__view">
				<Button variant="secondary" onclick={toggleRecipients}>
					{@html showRecipients ? eyeOffIcon : eyeIcon}
					{showRecipients ? 'Hide customers' : 'View customers'}
				</Button>
			</div>

			{@render recipientList()}
		{/if}
	</section>
{:else}
	<SectionBlock
		tone="growth"
		title="Recipients"
		icon={usersIcon}
		hint="Updates as you add or remove conditions above."
	>
		{#if countsQuery.isPending}
			<LoadingSkeleton variant="text" rows={2} label="Counting matching customers" />
		{:else if countsQuery.isError}
			<ErrorState
				title="The count could not be checked"
				description="Something went wrong. Try again."
				retry={() => countsQuery.refetch()}
			/>
		{:else if counts}
			<div class="group-preview__stats">
				<div class="group-preview__stat">
					<span class="group-preview__stat-value">{counts.matches}</span>
					<span class="group-preview__stat-label">Match the rules</span>
				</div>
				<div class="group-preview__stat">
					<span class="group-preview__stat-value">{counts.eligible}</span>
					<span class="group-preview__stat-label">Eligible to receive email</span>
				</div>
				<div class="group-preview__stat">
					<span class="group-preview__stat-value">{counts.excluded}</span>
					<span class="group-preview__stat-label">Excluded</span>
				</div>
			</div>

			{#if exclusionReasons.length > 0}
				<ul class="group-preview__reasons">
					{#each exclusionReasons as [reason, count] (reason)}
						<li>
							<span>{marketingExclusionReasonLabels[reason]}</span>
							<span class="group-preview__reason-count">{count}</span>
						</li>
					{/each}
				</ul>
			{/if}

			<div class="group-preview__toggle">
				<Button variant="secondary" size="small" onclick={toggleRecipients}>
					{@html eyeIcon}
					{showRecipients ? 'Hide customers' : 'View customers'}
				</Button>
			</div>

			{@render recipientList()}
		{/if}
	</SectionBlock>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The pop-up's side column: tinted in Marketing's colour, the counts in one white card.
	.group-preview--panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		box-sizing: border-box;
		height: 100%;
		padding: 20px;
		border-left: var(--border-base) solid var(--color-growth--surface-edge);
		background: var(--color-growth--surface);

		.group-preview__recipients {
			background: var(--color-surface);
		}

		.group-preview__recipient-reason {
			color: var(--color-text);
			background: var(--color-surface--background--subtle);
			border: var(--border-base) solid var(--color-border);
		}
	}

	.group-preview {
		&__panel-head {
			display: flex;
			align-items: flex-start;
			gap: 10px;

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}

			p {
				margin: 2px 0 0;
				color: var(--color-growth--onSurface);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__card {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-growth--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);
		}

		&__eligible {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__eligible-value {
			display: inline-flex;
			align-items: center;
			gap: 10px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-jumbo);
			font-weight: 700;
			letter-spacing: -1px;
			line-height: 1.1;
		}

		&__eligible-icon {
			display: inline-flex;
			color: var(--color-success);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__eligible-label {
			color: var(--color-success--onSurface);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__figures {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: var(--space-slim) 0 0;
			padding: var(--space-slim) 0 0;
			border-top: var(--border-base) solid var(--color-border);
			list-style: none;

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-text);
				font-size: var(--typography--fontSize-label);

				strong {
					color: var(--color-heading);
					font-size: var(--typography--fontSize-base);
					font-weight: 700;
				}
			}
		}

		&__figure-label {
			flex: 1 1 auto;
		}

		&__figure-icon {
			display: inline-flex;
			color: var(--color-growth);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		li.group-preview__figure-reason {
			padding-left: var(--space-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
		}

		&__view :global(.button) {
			width: 100%;
		}

		&__stats {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
			gap: var(--space-base);
		}

		&__stat {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__stat-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
		}

		&__stat-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__reasons {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				justify-content: space-between;
				padding: var(--space-smaller) 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				border-bottom: var(--border-base) solid var(--color-border);
			}
		}

		&__reason-count {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__toggle {
			display: flex;
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__recipients {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			overflow: hidden;

			li {
				display: flex;
				flex-wrap: wrap;
				align-items: center;
				gap: var(--space-small);
				padding: var(--space-small) var(--space-base);
				border-bottom: var(--border-base) solid var(--color-border);

				&:last-child {
					border-bottom: 0;
				}
			}
		}

		&__recipient-name {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-weight: 500;
		}

		&__recipient-email {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__recipient-reason {
			padding: 2px 8px;
			border-radius: var(--radius-large);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
