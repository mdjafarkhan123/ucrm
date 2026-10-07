<script lang="ts">
	import { resolve } from '$app/paths';
	import { useQueryClient } from '@tanstack/svelte-query';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowsMoveIcon from '@tabler/icons/outline/arrows-move.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import DealStepDialog from './DealStepDialog.svelte';
	import DealShareDialog from './DealShareDialog.svelte';
	import DealLostDialog from './DealLostDialog.svelte';
	import { formatUsd } from '$lib/jafar/packages';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		DEAL_NOTE_MAX,
		DEAL_STAGE_LABELS,
		LOST_REASON_LABELS,
		OPEN_DEAL_STAGES,
		STAGES_NEEDING_DATE,
		daysSince,
		latestShare,
		monthlyValue,
		prefetchDealPackages,
		refreshDeals,
		type BusinessDeal,
		type DealPriceShare,
		type OpenDealStage
	} from '$lib/jafar/deals';

	// Jafar business management B4: the Deal box on a business's page (plan § 4). It shows the open Deal -- its
	// stage, the prices exactly as they were shared, and any special terms -- or, when there is none, the latest
	// Lost one with a way to reopen it. The Deal's next step is the business's next action, shown in its own box.
	let {
		relationshipId,
		businessName,
		deals,
		doNotContact,
		current,
		canChange,
		canAgreeTerms,
		canRemove
	}: {
		relationshipId: string;
		businessName: string;
		/** Newest first; at most one is open. */
		deals: BusinessDeal[];
		/** The business asked not to be contacted: no new Deal, no reopening. */
		doNotContact: boolean;
		/** The business's next action now, if it has one. */
		current: { text: string; due_on: string } | null;
		canChange: boolean;
		canAgreeTerms: boolean;
		canRemove: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const open = $derived(deals.find((deal) => deal.stage !== 'lost') ?? null);
	const lastLost = $derived(open ? null : (deals.find((deal) => deal.stage === 'lost') ?? null));
	const shown = $derived(open ?? lastLost);
	const shared = $derived(shown ? latestShare(shown) : []);

	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });

	function daysLabel(iso: string) {
		const days = daysSince(iso);
		return days === 0 ? 'since today' : `for ${days} day${days === 1 ? '' : 's'}`;
	}

	function priceLine(share: DealPriceShare) {
		const parts = [];
		if (share.monthly_price_usd_cents !== null)
			parts.push(`${formatUsd(share.monthly_price_usd_cents)} a month`);
		if (share.yearly_price_usd_cents !== null)
			parts.push(`${formatUsd(share.yearly_price_usd_cents)} a year`);
		return parts.join(' · ');
	}

	function offerLines(share: DealPriceShare) {
		return Object.entries(share.offers ?? {}).flatMap(([billing, offer]) =>
			offer
				? [
						`${offer.name}: ${formatUsd(offer.intro_price_usd_cents)} for the first ${offer.periods} ${billing === 'year' ? 'year' : 'month'}${offer.periods === 1 ? '' : 's'}`
					]
				: []
		);
	}

	// --- Dialogs ----------------------------------------------------------------------------------------

	type Dialog =
		| { kind: 'start' }
		| { kind: 'move'; stage: OpenDealStage }
		| { kind: 'reopen' }
		| { kind: 'share' }
		| { kind: 'lost' }
		| { kind: 'remove' };
	let dialog = $state<Dialog | null>(null);
	let moving = $state(false);

	// Interested and Needs understood keep the next step, so they save straight away, as on the board.
	async function move(stage: OpenDealStage) {
		const deal = open;
		if (!deal || moving) return;
		if (STAGES_NEEDING_DATE.includes(stage) || current === null) {
			dialog = { kind: 'move', stage };
			return;
		}
		moving = true;
		const result = await sendLeadWrite(`/api/jafar/deals/${encodeURIComponent(deal.id)}`, 'PATCH', {
			stage
		});
		if (result.ok) await refreshDeals(queryClient, relationshipId);
		moving = false;
		if (result.ok) toast.success(`Moved to ${DEAL_STAGE_LABELS[stage]}`);
		else toast.error('The Deal could not be moved.', result.error);
	}

	const moveItems = $derived(
		open
			? [
					...OPEN_DEAL_STAGES.filter(
						(stage) => stage !== open.stage && stage !== 'pricing_shared'
					).map((stage) => ({
						key: stage,
						label: `Move to ${DEAL_STAGE_LABELS[stage]}`,
						onSelect: () => void move(stage)
					})),
					{ key: 'pricing', label: 'Share pricing…', onSelect: () => (dialog = { kind: 'share' }) }
				]
			: []
	);
	const moveFooter = [
		{ label: 'Mark as Lost…', destructive: true, onSelect: () => (dialog = { kind: 'lost' }) }
	];

	let menuOpen = $state(false);
	$effect(() => {
		if (menuOpen) void prefetchDealPackages(queryClient);
	});

	// --- Special terms ----------------------------------------------------------------------------------

	let editingTerms = $state(false);
	let termsDraft = $state('');
	let termsSaving = $state(false);
	let termsError = $state('');

	function editTerms() {
		termsDraft = open?.agreed_terms ?? '';
		termsError = '';
		editingTerms = true;
	}

	async function saveTerms(event: SubmitEvent) {
		event.preventDefault();
		const deal = open;
		if (!deal || termsSaving) return;
		termsSaving = true;
		termsError = '';
		const result = await sendLeadWrite(
			`/api/jafar/deals/${encodeURIComponent(deal.id)}/terms`,
			'PATCH',
			{ terms: termsDraft.trim() || null }
		);
		if (result.ok) await refreshDeals(queryClient, relationshipId);
		termsSaving = false;
		if (!result.ok) {
			termsError = result.fieldErrors.terms ?? result.error;
			return;
		}
		editingTerms = false;
		toast.success(termsDraft.trim() ? 'Agreed terms saved' : 'Agreed terms removed');
	}

	// --- Remove (Jafar only) ----------------------------------------------------------------------------

	let removing = $state(false);

	async function remove() {
		const deal = shown;
		if (!deal || removing) return;
		removing = true;
		const result = await sendLeadWrite(
			`/api/jafar/deals/${encodeURIComponent(deal.id)}/remove`,
			'POST'
		);
		if (result.ok) await refreshDeals(queryClient, relationshipId);
		removing = false;
		if (!result.ok) {
			toast.error('The Deal could not be removed.', result.error);
			return;
		}
		dialog = null;
		toast.success('Deal removed');
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RailCard title="Deal" icon={briefcaseIcon} class="deal-panel">
	{#if open}
		<div class="deal-panel__stage">
			<Badge status="informative" dot={false}>{DEAL_STAGE_LABELS[open.stage]}</Badge>
			<span class="deal-panel__since">{daysLabel(open.stage_entered_at)}</span>
			{#if canChange}
				<DropdownMenu
					items={moveItems}
					footer={moveFooter}
					triggerLabel="Change this Deal's stage"
					triggerClass="deal-panel__move"
					disabled={moving}
					bind:open={menuOpen}
				>
					{#snippet trigger()}
						<span class="deal-panel__button-icon" aria-hidden="true">{@html arrowsMoveIcon}</span
						>Change stage<span class="deal-panel__chevron" aria-hidden="true"
							>{@html chevronDownIcon}</span
						>
					{/snippet}
				</DropdownMenu>
			{/if}
		</div>
		{#if open.value_monthly_usd_cents !== null}
			<p class="deal-panel__value">
				<strong>{monthlyValue(open.value_monthly_usd_cents)}</strong>
				<span>if they buy the main package</span>
			</p>
		{/if}
	{:else if lastLost}
		<div class="deal-panel__stage">
			<Badge status="critical" dot={false}>Lost</Badge>
			{#if lastLost.lost_at}
				<span class="deal-panel__since">{dateFormat.format(new Date(lastLost.lost_at))}</span>
			{/if}
		</div>
		<dl class="deal-panel__facts">
			{#if lastLost.lost_reason}
				<div>
					<dt>Why</dt>
					<dd>{LOST_REASON_LABELS[lastLost.lost_reason]}</dd>
				</div>
			{/if}
			{#if lastLost.lost_from_stage}
				<div>
					<dt>Lost at</dt>
					<dd>{DEAL_STAGE_LABELS[lastLost.lost_from_stage]}</dd>
				</div>
			{/if}
			{#if lastLost.lost_note}
				<div>
					<dt>Note</dt>
					<dd class="deal-panel__prewrap">{lastLost.lost_note}</dd>
				</div>
			{/if}
		</dl>
	{:else}
		<p class="deal-panel__empty">
			{doNotContact
				? 'No Deal. This business asked not to be contacted.'
				: 'No Deal yet. Start one when they show interest or agree to a call.'}
		</p>
	{/if}

	{#if shared.length}
		<section class="deal-panel__section" aria-label="Prices shared">
			<h3>
				Prices shared <span
					>{dateFormat.format(new Date(shared[0].shared_at))} · kept as they were then</span
				>
			</h3>
			<ul class="deal-panel__shares">
				{#each shared as share, index (share.package_slug)}
					<li>
						<div class="deal-panel__share-top">
							<strong>{share.package_name}</strong>
							{#if index === 0 && shared.length > 1}<Badge size="small">Main</Badge>{/if}
							<!-- eslint-disable svelte/no-navigation-without-resolve -- the full link that was shared. -->
							<a
								class="deal-panel__share-link"
								href={share.link}
								target="_blank"
								rel="noopener noreferrer"
								aria-label={`Open the ${share.package_name} link that was shared`}
								title="Open the shared link">{@html externalLinkIcon}</a
							>
							<!-- eslint-enable svelte/no-navigation-without-resolve -->
						</div>
						<span>{priceLine(share)}</span>
						{#each offerLines(share) as line (line)}
							<span class="deal-panel__offer">{line}</span>
						{/each}
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if open && (open.agreed_terms || canAgreeTerms)}
		<section class="deal-panel__section" aria-label="Agreed special terms">
			<div class="deal-panel__section-head">
				<h3>Special terms</h3>
				{#if canAgreeTerms && !editingTerms}
					<PencilButton label="Edit the agreed special terms" onclick={editTerms} />
				{/if}
			</div>
			{#if editingTerms}
				<form class="deal-panel__terms-form" onsubmit={saveTerms} novalidate>
					<Textarea
						id="deal-terms"
						label="What was agreed"
						rows={3}
						maxlength={DEAL_NOTE_MAX}
						invalid={Boolean(termsError)}
						errorMessage={termsError}
						bind:value={termsDraft}
					/>
					<div class="deal-panel__buttons">
						<Button
							variant="tertiary"
							size="small"
							disabled={termsSaving}
							onclick={() => (editingTerms = false)}>Cancel</Button
						>
						<Button type="submit" variant="primary" size="small" loading={termsSaving}>Save</Button>
					</div>
				</form>
			{:else if open.agreed_terms}
				<p class="deal-panel__terms">{open.agreed_terms}</p>
				{#if open.agreed_terms_by_email && open.agreed_terms_at}
					<p class="deal-panel__muted">
						Agreed by {open.agreed_terms_by_email} · {dateFormat.format(
							new Date(open.agreed_terms_at)
						)}
					</p>
				{/if}
			{:else}
				<p class="deal-panel__muted">None. Add a discount or other exception you agreed.</p>
			{/if}
		</section>
	{/if}

	{#if canChange && !doNotContact && !open}
		<div class="deal-panel__buttons">
			{#if lastLost}
				<Button variant="secondary" size="small" onclick={() => (dialog = { kind: 'reopen' })}>
					<span class="deal-panel__button-icon" aria-hidden="true">{@html refreshIcon}</span>Reopen
				</Button>
			{/if}
			<Button
				variant={lastLost ? 'tertiary' : 'primary'}
				size="small"
				onclick={() => (dialog = { kind: 'start' })}
			>
				<span class="deal-panel__button-icon" aria-hidden="true">{@html plusIcon}</span>{lastLost
					? 'Start a new Deal'
					: 'Start a Deal'}
			</Button>
		</div>
	{/if}

	{#if shown}
		<div class="deal-panel__footer">
			{#if open}
				<a href={resolve('/jafar/deals')}>See the board</a>
			{/if}
			{#if canRemove}
				<button
					type="button"
					class="deal-panel__remove"
					onclick={() => (dialog = { kind: 'remove' })}
				>
					<span aria-hidden="true">{@html trashIcon}</span>Remove Deal
				</button>
			{/if}
		</div>
	{/if}
</RailCard>
<!-- eslint-enable svelte/no-at-html-tags -->

{#if dialog?.kind === 'start'}
	<DealStepDialog
		action={{ kind: 'start', relationshipId }}
		{businessName}
		{current}
		onClose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'move' && open}
	<DealStepDialog
		action={{ kind: 'move', dealId: open.id, relationshipId, stage: dialog.stage }}
		{businessName}
		{current}
		onClose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'reopen' && lastLost?.lost_from_stage}
	<DealStepDialog
		action={{
			kind: 'reopen',
			dealId: lastLost.id,
			relationshipId,
			stage: lastLost.lost_from_stage
		}}
		{businessName}
		{current}
		onClose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'share' && open}
	<DealShareDialog
		dealId={open.id}
		{relationshipId}
		{businessName}
		onClose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'lost' && open}
	<DealLostDialog
		dealId={open.id}
		{relationshipId}
		{businessName}
		onClose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'remove' && shown}
	<ConfirmDialog
		open={true}
		title="Remove this Deal?"
		confirmLabel="Remove"
		loading={removing}
		onConfirm={remove}
		onClose={() => (dialog = null)}
	>
		<p>
			Only for a Deal started by mistake. Its stages, shared prices and terms are deleted, and {businessName}
			goes back to the Leads list. To record that they said no, mark it Lost instead.
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.deal-panel {
		&__stage {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			:global(.deal-panel__move) {
				display: inline-flex;
				align-items: center;
				margin-left: auto;
				padding: var(--space-smaller) var(--space-small);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				color: var(--color-heading);
				font: inherit;
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
				cursor: pointer;
				transition: background-color var(--timing-quick);

				&:hover:not(:disabled) {
					background: var(--color-surface--hover);
				}

				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}

				&:disabled {
					cursor: progress;
					opacity: 0.6;
				}
			}
		}

		&__chevron {
			display: inline-flex;
			margin-left: var(--space-smaller);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__since,
		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__value {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-small);
			margin: var(--space-small) 0 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__facts {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: var(--space-small) 0 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 700;
			}

			dd {
				margin: 2px 0 0;
				color: var(--color-text);
				overflow-wrap: anywhere;
			}
		}

		&__section {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				display: flex;
				flex-wrap: wrap;
				align-items: baseline;
				gap: var(--space-smaller) var(--space-small);
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;

				span {
					color: var(--color-text--secondary);
					font-size: var(--typography--fontSize-small);
					font-weight: 400;
				}
			}
		}

		&__section-head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__shares {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				flex-direction: column;
				gap: 2px;
				padding: var(--space-small);
				border-radius: var(--radius-base);
				background: var(--color-surface--background--subtle);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__share-top {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			strong {
				min-width: 0;
				flex: 1;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				overflow-wrap: anywhere;
			}
		}

		&__share-link {
			display: grid;
			width: 28px;
			height: 28px;
			flex: none;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-interactive);

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__offer {
			color: var(--color-success--onSurface);
			font-weight: 600;
		}

		&__terms {
			margin: 0;
			color: var(--color-text);
			white-space: pre-wrap;
			overflow-wrap: anywhere;
		}

		&__muted {
			margin: 0;
		}

		&__terms-form {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__buttons {
			display: flex;
			flex-wrap: wrap;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-base);
		}

		&__terms-form &__buttons {
			margin-top: 0;
		}

		&__button-icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__prewrap {
			white-space: pre-wrap;
		}

		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			margin-top: var(--space-base);
			padding-top: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
			font-size: var(--typography--fontSize-small);

			a {
				color: var(--color-interactive);
				font-weight: 600;
				text-decoration: underline;
				text-underline-offset: 3px;

				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}
			}
		}

		&__remove {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			margin-left: auto;
			padding: var(--space-smaller);
			border: 0;
			border-radius: var(--radius-base);
			background: transparent;
			color: var(--color-text--secondary);
			font: inherit;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-critical);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
