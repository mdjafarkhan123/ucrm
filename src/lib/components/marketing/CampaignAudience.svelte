<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import { fetchGroupPreviewRecipients, type RecipientPreviewPage } from '$lib/marketing/api';
	import {
		marketingExclusionReasonLabels,
		type MarketingExclusionReason,
		type MarketingGroupRules,
		type MarketingPreviewRecipient,
		type MarketingRecipientPreviewCounts
	} from '$lib/marketing/customer-groups';
	import mailCheckIcon from '@tabler/icons/outline/mail-check.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import mailXIcon from '@tabler/icons/outline/mail-x.svg?raw';
	import mailMinusIcon from '@tabler/icons/outline/mail-minus.svg?raw';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import bellOffIcon from '@tabler/icons/outline/bell-off.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import shieldOffIcon from '@tabler/icons/outline/shield-off.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';

	// Who will get this campaign (design skill `layout.md` → Setup steps → New campaign · Customers step): the
	// audience meter, the reasons customers are left out and, on request, the customers themselves. The step
	// owns the count query so its footer can say the same number; this part draws it and loads the bounded
	// customer list only when "View customers" is pressed (CLAUDE.md rule 10).
	let {
		rules,
		counts,
		isPending,
		isError,
		onRetry,
		meterOnly = false
	}: {
		rules: MarketingGroupRules;
		counts: MarketingRecipientPreviewCounts | undefined;
		isPending: boolean;
		isError: boolean;
		onRetry: () => void;
		/** The Review step shows only the headline meter, not the left-out reasons or the customer list. */
		meterOnly?: boolean;
	} = $props();

	// Each reason a matched customer is left out: its icon, what the owner can do about it, and whether the
	// owner can fix it (warning colour) or it is a choice the customer made (grey).
	const REASONS: Record<MarketingExclusionReason, { icon: string; tip: string; fixable: boolean }> =
		{
			inactive_customer: {
				icon: archiveIcon,
				tip: 'Archived customers are never emailed.',
				fixable: false
			},
			missing_email: {
				icon: mailXIcon,
				tip: 'Add an email on the client to reach them.',
				fixable: true
			},
			unsubscribed: {
				icon: mailMinusIcon,
				tip: 'They asked not to get marketing email.',
				fixable: false
			},
			complaint: {
				icon: alertIcon,
				tip: 'They reported an earlier email as spam.',
				fixable: false
			},
			hard_bounce: {
				icon: mailOffIcon,
				tip: 'Earlier emails could not be delivered. Check the address.',
				fixable: true
			},
			do_not_disturb: {
				icon: bellOffIcon,
				tip: 'They asked not to be contacted.',
				fixable: false
			},
			no_marketing: {
				icon: banIcon,
				tip: 'Marketing is switched off for them.',
				fixable: false
			},
			no_consent: {
				icon: shieldOffIcon,
				tip: 'Record their permission on the client to reach them.',
				fixable: true
			},
			recent_marketing: {
				icon: hourglassIcon,
				tip: 'Rested so nobody gets emailed too often.',
				fixable: false
			},
			duplicate_destination: {
				icon: copyIcon,
				tip: 'Another customer with the same email gets it instead.',
				fixable: false
			}
		};

	const reasons = $derived(
		(Object.entries(counts?.excluded_by_reason ?? {}) as [MarketingExclusionReason, number][])
			.filter(([, count]) => count > 0)
			.sort((a, b) => b[1] - a[1])
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
			pages = [await fetchGroupPreviewRecipients(rules, { status: statusFilter })];
		} catch (error) {
			listError = error instanceof Error ? error.message : 'The customer list could not be loaded.';
		} finally {
			loadingMore = false;
		}
	}

	async function loadMore() {
		loadingMore = true;
		listError = '';
		try {
			pages = [...pages, await fetchGroupPreviewRecipients(rules, pageCursor())];
		} catch (error) {
			listError = error instanceof Error ? error.message : 'The customer list could not be loaded.';
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
	const hasMore = $derived((pages.at(-1) ?? []).length === 50);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="audience">
	{#if isPending}
		<div
			class="audience__meter audience__meter--counting"
			role="status"
			aria-label="Counting who will get this email"
		>
			<div class="audience__top">
				<span class="audience__bone audience__bone--tile"></span>
				<span class="audience__bone audience__bone--number"></span>
				<span class="audience__bones">
					<span class="audience__bone audience__bone--line"></span>
					<span class="audience__bone audience__bone--line audience__bone--short"></span>
				</span>
			</div>
			<span class="audience__bone audience__bone--bar"></span>
			<span class="audience__bone audience__bone--key"></span>
		</div>
	{:else if isError}
		<div class="audience__error">
			<ErrorState
				title="The count could not be checked"
				description="Something went wrong. Try again."
				retry={onRetry}
				size="small"
			/>
		</div>
	{:else if counts}
		<div class="audience__meter">
			<div class="audience__top">
				<IconTile icon={mailCheckIcon} tone="success" white />
				<div class="audience__figure">
					<span class="audience__number">{counts.eligible}</span>
					<span class="audience__words">
						<b>{counts.eligible === 1 ? 'customer' : 'customers'} will get this email</b>
						<span>out of {counts.matches} who match the group's rules</span>
					</span>
				</div>
			</div>
			<div class="audience__bar" aria-hidden="true">
				{#if counts.eligible > 0}
					<span class="audience__bar-yes" style:flex-grow={counts.eligible}></span>
				{/if}
				{#if counts.excluded > 0}
					<span class="audience__bar-no" style:flex-grow={counts.excluded}></span>
				{/if}
			</div>
			<ul class="audience__key">
				<li><span class="audience__dot audience__dot--yes"></span>{counts.eligible} will get it</li>
				{#if counts.excluded > 0}
					<li><span class="audience__dot audience__dot--no"></span>{counts.excluded} left out</li>
				{/if}
			</ul>
		</div>

		{#if meterOnly}
			<!-- The Review step stops at the meter. -->
		{:else if counts.matches === 0}
			<p class="audience__none">
				No customers match this group's rules yet. Change the group or pick another.
			</p>
		{:else}
			<section class="audience__left-out">
				<header class="audience__head">
					<div class="audience__head-words">
						{#if counts.excluded > 0}
							<h3>Why {counts.excluded} {counts.excluded === 1 ? 'is' : 'are'} left out</h3>
							<p>They match the group but won't be emailed.</p>
						{:else}
							<h3>Everyone who matches will get it</h3>
							<p>Nobody in this group is left out.</p>
						{/if}
					</div>
					<Button variant="secondary" onclick={toggleRecipients}>
						<span class="audience__button-icon" aria-hidden="true"
							>{@html showRecipients ? eyeOffIcon : eyeIcon}</span
						>
						{showRecipients ? 'Hide customers' : 'View customers'}
					</Button>
				</header>

				{#if reasons.length > 0}
					<ul class="audience__reasons">
						{#each reasons as [reason, count] (reason)}
							<li class="audience__reason">
								<IconTile
									icon={REASONS[reason].icon}
									tone={REASONS[reason].fixable ? 'warning' : 'inactive'}
									size={32}
								/>
								<span class="audience__reason-words">
									<b>{marketingExclusionReasonLabels[reason]}</b>
									<span>{REASONS[reason].tip}</span>
								</span>
								<strong>{count}</strong>
							</li>
						{/each}
					</ul>
				{/if}
			</section>

			{#if showRecipients}
				<section class="audience__customers">
					<header class="audience__head">
						<h3>Customers in this group</h3>
						<Select
							id="campaign-audience-filter"
							class="audience__filter"
							ariaLabel="Filter customers"
							value={statusFilter}
							options={[
								{ value: 'all', label: 'All matches' },
								{ value: 'eligible', label: 'Will get it' },
								{ value: 'excluded', label: 'Left out' }
							]}
							onchange={onStatusChange}
						/>
					</header>

					{#if listError}
						<div class="audience__error">
							<ErrorState description={listError} retry={loadFirstPage} size="small" />
						</div>
					{:else if loadingMore && pages.length === 0}
						<ul class="audience__list" aria-busy="true" aria-label="Loading customers">
							{#each [0, 1, 2, 3] as row (row)}
								<li class="audience__customer">
									<span class="audience__customer-words">
										<span class="audience__bone audience__bone--line"></span>
										<span class="audience__bone audience__bone--line audience__bone--short"></span>
									</span>
								</li>
							{/each}
						</ul>
					{:else if flatRecipients.length === 0}
						<p class="audience__none">No customers match this filter.</p>
					{:else}
						<div class="audience__list-box">
							<ul class="audience__list">
								{#each flatRecipients as recipient (recipient.client_id)}
									<li class="audience__customer">
										<span class="audience__customer-words">
											<b>{recipient.display_name}</b>
											<span>{recipient.email ?? 'No email address'}</span>
										</span>
										{#if recipient.excluded_reason}
											<span class="audience__pill">
												{marketingExclusionReasonLabels[recipient.excluded_reason]}
											</span>
										{:else}
											<span class="audience__will-get">
												<span class="audience__will-get-icon" aria-hidden="true"
													>{@html mailCheckIcon}</span
												>
												Will get it
											</span>
										{/if}
									</li>
								{/each}
							</ul>
							<ListLoadMore
								count={flatRecipients.length}
								recordName="customers"
								hasNextPage={hasMore}
								isFetchingNextPage={loadingMore}
								onLoadMore={loadMore}
								label="Load more"
							/>
						</div>
					{/if}
				</section>
			{/if}
		{/if}
	{/if}
</div>

<style lang="scss">
	.audience {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);
	}

	// The meter: Marketing's tint, so the number reads as the headline of the step.
	.audience__meter {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: var(--space-medium);
		border: var(--border-base) solid var(--color-growth--surface-edge);
		border-radius: var(--radius-large);
		background: var(--color-growth--surface);
	}

	.audience__top {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.audience__figure {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		min-width: 0;
	}

	.audience__number {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-stat);
		font-weight: 700;
		letter-spacing: -1px;
		line-height: 1.2;
	}

	.audience__words {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;

		b {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		span {
			color: var(--color-growth--onSurface);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.audience__bar {
		display: flex;
		gap: 2px;
		height: 10px;
		overflow: hidden;
		border-radius: 5px;
		background: var(--color-surface);

		&-yes,
		&-no {
			flex-basis: 0;
			min-width: 6px;
		}
		&-yes {
			background: var(--color-success);
		}
		&-no {
			background: var(--color-inactive);
		}
	}

	.audience__key {
		display: flex;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		li {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
	}

	.audience__dot {
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);

		&--yes {
			background: var(--color-success);
		}
		&--no {
			background: var(--color-inactive);
		}
	}

	// The meter while the count is being worked out: bones in the tint's own edge colour.
	.audience__bones {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.audience__bone {
		display: block;
		border-radius: var(--radius-small);
		background: var(--color-growth--surface-edge);

		&--tile {
			width: 40px;
			height: 40px;
			border-radius: var(--radius-tile-large);
		}
		&--number {
			width: 72px;
			height: 36px;
			border-radius: var(--radius-base);
		}
		&--line {
			width: 220px;
			height: 12px;
		}
		&--short {
			width: 150px;
		}
		&--bar {
			height: 10px;
			border-radius: 5px;
		}
		&--key {
			width: 180px;
			height: 12px;
		}
	}

	.audience__customers .audience__bone,
	.audience__list .audience__bone {
		background: var(--color-border);
	}

	.audience__error {
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
	}

	.audience__none {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.audience__left-out,
	.audience__customers {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
	}

	.audience__head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);

		h3 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		p {
			margin: 2px 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.audience__head :global(.audience__filter) {
		width: 200px;
	}

	.audience__button-icon {
		display: inline-flex;
	}

	.audience__reasons,
	.audience__list-box {
		margin: 0;
		padding: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: 12px;
		background: var(--color-surface);
		list-style: none;
	}

	.audience__list {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.audience__list-box .audience__list {
		border: 0;
	}

	.audience__reason {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-base);

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
	}

	.audience__reason-words,
	.audience__customer-words {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 2px;
		min-width: 0;

		b {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
		}
		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.audience__reason-words b {
		font-weight: 500;
	}

	.audience__customer {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: 10px var(--space-base);

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		.audience__customer-words b {
			font-weight: 600;
		}
	}

	.audience__list[aria-busy='true'] {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: 12px;
		background: var(--color-surface);
	}

	.audience__pill {
		flex: none;
		padding: 2px 10px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-circle);
		background: var(--color-surface--background--subtle);
		color: var(--color-text);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 500;
	}

	.audience__will-get {
		display: inline-flex;
		flex: none;
		align-items: center;
		gap: 6px;
		color: var(--color-success--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 500;
	}

	.audience__will-get-icon {
		display: inline-flex;
		color: var(--color-success);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
</style>
