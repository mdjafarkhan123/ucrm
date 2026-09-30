<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, keepPreviousData } from '@tanstack/svelte-query';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import type {
		BillingCommandInput,
		OrganizationBilling,
		PackageAllowanceSide,
		PackageChangePreview,
		PackageChangeTiming
	} from '$lib/components/jafar/organization/types';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { fetchPackages } from '$lib/jafar/packages';
	import { offerDiscount, offerLength } from '$lib/packages/public-package';
	import { jafarPackageChangePreviewKey, jafarPackagesKey } from '$lib/jafar/query-keys';
	import { formatCalendarDate, formatPeriod, formatUsd } from './format';

	// Package builder P8b: Jafar picks a published edition, billing, and start; the database previews both
	// editions side by side, what is gained and lost, and the payment effect; he confirms exactly that. The
	// Billing tab mounts this fresh for each opening and sends the command with the opening's idempotency key.
	let {
		organizationId,
		billing,
		pending,
		error,
		fieldErrors,
		onSubmit,
		onClose
	}: {
		organizationId: string;
		billing: OrganizationBilling;
		pending: boolean;
		error: string;
		fieldErrors: Record<string, string>;
		onSubmit: (command: BillingCommandInput) => void;
		onClose: () => void;
	} = $props();

	const opening = untrack(() => ({
		interval: billing.current_agreement?.billing_interval ?? 'month',
		// Next renewal is the normal start (plan § Assignment and changes); without a paid period to renew,
		// only "now" is possible.
		timing: (billing.paid_through_date && billing.paid_through_date >= billing.today
			? 'next_renewal'
			: 'now') as PackageChangeTiming
	}));

	const catalogQuery = createQuery(() => ({
		queryKey: jafarPackagesKey,
		queryFn: fetchPackages,
		staleTime: 30_000
	}));
	const choices = $derived(
		(catalogQuery.data ?? []).filter((pkg) => pkg.published && !pkg.archived_at)
	);

	let packageId = $state('');
	let interval = $state<'month' | 'year'>(opening.interval);
	let timing = $state<PackageChangeTiming>(opening.timing);
	let reason = $state('');
	let reasonError = $state('');
	// P11b: no offer, an automatic offer by id, or 'code' for one Jafar types. Keeping the running offer is
	// a separate tick box, off by default (Jafar, 2026-09-30).
	let offerChoice = $state('');
	let codeText = $state('');
	let appliedCode = $state('');
	let keepOffer = $state(false);
	const offerRequest = $derived({
		offerId: offerChoice && offerChoice !== 'code' ? offerChoice : null,
		code: offerChoice === 'code' && appliedCode ? appliedCode : null,
		keep: keepOffer
	});
	const runningOffer = $derived(
		billing.current_agreement?.offer_terms &&
			billing.current_agreement.offer_terms.ends_before > billing.today
			? billing.current_agreement.offer_terms
			: null
	);

	function resetOffer() {
		offerChoice = '';
		codeText = '';
		appliedCode = '';
	}

	const chosen = $derived(choices.find((pkg) => pkg.id === packageId) ?? null);
	const chosenPrice = (period: 'month' | 'year') =>
		period === 'month'
			? (chosen?.published?.monthly_price_usd_cents ?? null)
			: (chosen?.published?.yearly_price_usd_cents ?? null);

	const renewalAvailable = $derived(
		Boolean(billing.paid_through_date && billing.paid_through_date >= billing.today)
	);

	const previewQuery = createQuery(() => ({
		queryKey: jafarPackageChangePreviewKey(
			organizationId,
			chosen?.published?.edition_id ?? '',
			interval,
			timing,
			offerRequest
		),
		queryFn: async (): Promise<PackageChangePreview> => {
			const params = new URLSearchParams({
				edition_id: chosen?.published?.edition_id ?? '',
				billing_interval: interval,
				timing
			});
			if (offerRequest.offerId) params.set('offer_id', offerRequest.offerId);
			if (offerRequest.code) params.set('offer_code', offerRequest.code);
			if (offerRequest.keep) params.set('keep_offer', 'true');
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/billing/change-preview?${params}`
			);
			const result = (await response.json()) as { preview?: PackageChangePreview; error?: string };
			if (!response.ok || !result.preview)
				throw new Error(result.error ?? 'The change could not be previewed.');
			return result.preview;
		},
		enabled: Boolean(chosen?.published),
		staleTime: 0,
		// Changing the offer keeps the comparison on screen while the new figures load.
		placeholderData: keepPreviousData
	}));
	const preview = $derived(previewQuery.data ?? null);

	const gained = $derived(
		preview?.capabilities.filter((row) => row.proposed && !row.current) ?? []
	);
	const lost = $derived(preview?.capabilities.filter((row) => row.current && !row.proposed) ?? []);
	const changedAllowances = $derived(
		preview?.allowances.filter(
			(row) => row.current.state !== row.proposed.state || row.current.value !== row.proposed.value
		) ?? []
	);
	const otherBlockers = $derived(
		preview?.blockers.filter((blocker) => blocker.code !== 'over_limits') ?? []
	);
	const money = $derived(preview?.money ?? null);
	const payNow = $derived(
		money?.new_charge ? money.new_charge.amount_usd_cents - money.credit_applied_usd_cents : 0
	);
	const leftoverCredit = $derived(
		money ? money.credit_usd_cents - money.credit_applied_usd_cents : 0
	);
	const intervalChanges = $derived(
		preview ? preview.current?.billing_interval !== preview.proposed.billing_interval : false
	);
	const canConfirm = $derived(
		Boolean(preview && preview.blockers.length === 0 && !previewQuery.isFetching && !pending)
	);

	function allowanceText(side: PackageAllowanceSide, unit: string, monthly: boolean) {
		if (side.state === 'unlimited') return 'Unlimited';
		if (side.state === 'not_included') return 'Not included';
		return `${(side.value ?? 0).toLocaleString('en-US')} ${unit}${monthly ? ' a month' : ''}`;
	}
	function perInterval(value: 'month' | 'year') {
		return value === 'month' ? 'a month' : 'a year';
	}
	function offerSummary(terms: NonNullable<PackageChangePreview['offer']['proposed']>) {
		return `${offerDiscount(terms)} ${offerLength(terms.billing_interval, terms.periods)}`;
	}

	function submit(event: SubmitEvent) {
		event.preventDefault();
		reasonError = '';
		if (!preview || !canConfirm || !preview.effective_date) return;
		if (reason.trim().length < 3) {
			reasonError = 'Enter a reason of at least 3 characters.';
			return;
		}
		onSubmit({
			action: 'change_package',
			edition_id: preview.proposed.edition_id,
			billing_interval: preview.proposed.billing_interval,
			timing: preview.timing,
			expected_effective_date: preview.effective_date,
			expected_credit_usd_cents: preview.money.credit_usd_cents,
			expected_charge_usd_cents: preview.money.new_charge?.amount_usd_cents ?? 0,
			reason: reason.trim(),
			offer_id: offerRequest.offerId,
			offer_code: offerRequest.code,
			keep_offer: offerRequest.keep
		});
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog open title="Change package" size="large" {onClose}>
	<form class="package-change" onsubmit={submit} novalidate>
		<div class="package-change__choices">
			<Select
				id="package-change-package"
				label="New package"
				placeholder={catalogQuery.isPending ? 'Loading packages…' : 'Choose a package'}
				bind:value={packageId}
				options={choices.map((pkg) => ({
					value: pkg.id,
					label: `${pkg.published?.name} · edition ${pkg.published?.edition_number}${pkg.visibility === 'private' ? ' · private' : ''}`
				}))}
				onchange={() => {
					if (chosen && chosenPrice(interval) === null)
						interval = interval === 'month' ? 'year' : 'month';
					resetOffer();
				}}
			/>
			<SegmentedControl
				label="Billing"
				fullWidth
				bind:value={
					() => interval,
					(value) => {
						interval = value as 'month' | 'year';
						resetOffer();
					}
				}
				options={[
					{
						value: 'month',
						label: chosen?.published?.monthly_price_usd_cents
							? `Monthly · ${formatUsd(chosen.published.monthly_price_usd_cents)}`
							: 'Monthly',
						disabled: Boolean(chosen) && chosenPrice('month') === null,
						title: 'This package has no monthly price'
					},
					{
						value: 'year',
						label: chosen?.published?.yearly_price_usd_cents
							? `Yearly · ${formatUsd(chosen.published.yearly_price_usd_cents)}`
							: 'Yearly',
						disabled: Boolean(chosen) && chosenPrice('year') === null,
						title: 'This package has no yearly price'
					}
				]}
			/>
			<SegmentedControl
				label="Starts"
				fullWidth
				bind:value={() => timing, (value) => (timing = value as PackageChangeTiming)}
				options={[
					{
						value: 'next_renewal',
						label: renewalAvailable
							? `Next renewal · ${formatCalendarDate(billing.next_renewal_date)}`
							: 'Next renewal',
						disabled: !renewalAvailable,
						title: 'There is no paid period to renew yet'
					},
					{ value: 'now', label: 'Now' }
				]}
			/>
		</div>

		{#if !chosen}
			<p class="package-change__hint">
				Choose a published package to see what changes for this customer. Existing records stay as
				they are whichever package they move to.
			</p>
		{:else if previewQuery.isPending}
			<div class="package-change__loading" aria-busy="true">
				<LoadingSkeleton variant="card" label="Loading the comparison" />
				<LoadingSkeleton variant="card" label="Loading the payment effect" />
			</div>
		{:else if previewQuery.isError}
			<Banner type="error">{previewQuery.error.message}</Banner>
		{:else if preview}
			{#if otherBlockers.length}
				<Banner type="warning">
					<ul class="package-change__blockers">
						{#each otherBlockers as blocker (blocker.code)}<li>{blocker.message}</li>{/each}
					</ul>
				</Banner>
			{/if}

			<div class="package-change__compare">
				<div class="package-change__side">
					<p class="package-change__eyebrow">Now</p>
					{#if preview.current}
						<h3>{preview.current.name}</h3>
						<p>
							Edition {preview.current.edition_number} · {formatUsd(
								preview.current.agreed_price_usd_cents
							)}
							{perInterval(preview.current.billing_interval)}
						</p>
					{:else}
						<h3>No package</h3>
					{/if}
				</div>
				<div class="package-change__side package-change__side--new">
					<p class="package-change__eyebrow">
						From {formatCalendarDate(preview.effective_date)}
					</p>
					<h3>{preview.proposed.name}</h3>
					<p>
						Edition {preview.proposed.edition_number} · {preview.proposed.price_usd_cents === null
							? 'no price'
							: formatUsd(preview.proposed.price_usd_cents)}
						{perInterval(preview.proposed.billing_interval)}
						{#if preview.proposed.visibility === 'private'}
							<Badge status="inactive" size="small">Private</Badge>
						{/if}
					</p>
				</div>
			</div>

			<section class="package-change__block" aria-labelledby="package-change-features">
				<h4 id="package-change-features">Features</h4>
				{#if gained.length === 0 && lost.length === 0}
					<p class="package-change__hint">The same features.</p>
				{:else}
					<div class="package-change__feature-groups">
						{#if gained.length}
							<div>
								<p class="package-change__eyebrow">Added</p>
								<ul class="package-change__features">
									{#each gained as row (row.capability_key)}
										<li class="package-change__feature package-change__feature--gained">
											<span aria-hidden="true">{@html plusIcon}</span>
											{row.label}
										</li>
									{/each}
								</ul>
							</div>
						{/if}
						{#if lost.length}
							<div>
								<p class="package-change__eyebrow">Removed</p>
								<ul class="package-change__features">
									{#each lost as row (row.capability_key)}
										<li class="package-change__feature package-change__feature--lost">
											<span aria-hidden="true">{@html minusIcon}</span>
											{row.label}
											{#if row.exception === 'on'}
												<em>— kept on by an exception until it ends</em>
											{/if}
										</li>
									{/each}
								</ul>
							</div>
						{/if}
					</div>
				{/if}
			</section>

			<section class="package-change__block" aria-labelledby="package-change-limits">
				<h4 id="package-change-limits">Limits</h4>
				{#if changedAllowances.length === 0}
					<p class="package-change__hint">The same limits.</p>
				{:else}
					<table class="package-change__table">
						<thead>
							<tr>
								<th scope="col">Limit</th>
								<th scope="col">Now</th>
								<th scope="col">New</th>
								<th scope="col" class="align-end">In use</th>
							</tr>
						</thead>
						<tbody>
							{#each changedAllowances as row (row.allowance_key)}
								<tr class:package-change__row--over={row.excess > 0}>
									<th scope="row">{row.label}</th>
									<td>{allowanceText(row.current, row.unit, row.resets_monthly)}</td>
									<td>
										{allowanceText(row.proposed, row.unit, row.resets_monthly)}
										{#if row.exception}
											<span class="package-change__note"
												>exception: {allowanceText(
													row.exception,
													row.unit,
													row.resets_monthly
												)}</span
											>
										{/if}
									</td>
									<td class="align-end">{row.in_use ?? '—'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{/if}
				{#if preview.over_limits.length}
					<Banner type="warning">
						<div>
							<strong>Sort these out first.</strong> The customer uses more than the new package
							allows:
							<ul class="package-change__blockers">
								{#each preview.over_limits as row (row.allowance_key)}
									<li>
										{row.label}: {row.in_use} in use, new limit {allowanceText(
											row.exception ?? row.proposed,
											row.unit,
											false
										)} — remove {row.excess}.
									</li>
								{/each}
							</ul>
						</div>
					</Banner>
				{/if}
			</section>

			<section class="package-change__block" aria-labelledby="package-change-offer">
				<h4 id="package-change-offer">Intro offer</h4>
				{#if runningOffer}
					<Checkbox
						id="package-change-keep-offer"
						label={`Keep the current offer: ${offerSummary(runningOffer)}`}
						description={preview.offer.can_keep || keepOffer
							? `It keeps its end date: the normal price starts ${formatCalendarDate(runningOffer.ends_before)}. The discount applies to the new price.`
							: 'Only possible when the billing stays the same and the offer is still running on the day the change starts.'}
						disabled={!preview.offer.can_keep && !keepOffer}
						bind:checked={keepOffer}
						onchange={(checked) => checked && resetOffer()}
					/>
				{/if}
				{#if !keepOffer}
					<div class="package-change__offer-choice">
						<Select
							id="package-change-offer-choice"
							label="Add an offer"
							bind:value={
								() => offerChoice,
								(value) => {
									offerChoice = value;
									codeText = '';
									appliedCode = '';
								}
							}
							options={[
								{ value: '', label: 'No offer' },
								...preview.offer.available.map((offer) => ({
									value: offer.id,
									label: `${offer.name} · ${offerDiscount(offer)} ${offerLength(offer.billing_interval, offer.periods)}`
								})),
								{ value: 'code', label: 'Enter a code…' }
							]}
						/>
						{#if offerChoice === 'code'}
							<div class="package-change__code">
								<Input
									id="package-change-offer-code"
									label="Offer code"
									bind:value={() => codeText, (value) => (codeText = String(value).toUpperCase())}
								/>
								<Button
									type="button"
									variant="secondary"
									disabled={!codeText.trim() || codeText.trim() === appliedCode}
									onclick={() => (appliedCode = codeText.trim())}>Apply</Button
								>
							</div>
						{/if}
					</div>
				{/if}
				{#if preview.offer.proposed}
					{@const terms = preview.offer.proposed}
					<p class="package-change__offer">
						<strong>{terms.name}: {offerSummary(terms)}.</strong>
						{formatUsd(terms.intro_price_usd_cents)}
						{perInterval(terms.billing_interval)} from {formatCalendarDate(terms.starts_on)}, then
						{formatUsd(terms.normal_price_usd_cents)}
						{perInterval(terms.billing_interval)} from {formatCalendarDate(terms.ends_before)}.
					</p>
				{:else if runningOffer && !keepOffer}
					<p class="package-change__hint">
						The current offer stops with this change, so the new package is charged at its normal
						price.
					</p>
				{:else if preview.offer.available.length === 0 && offerChoice === ''}
					<p class="package-change__hint">
						No automatic offer fits this customer, package, and billing. You can still enter a code.
					</p>
				{/if}
			</section>

			<section class="package-change__block" aria-labelledby="package-change-money">
				<h4 id="package-change-money">Payment</h4>
				{#if money}
					<dl class="package-change__money">
						{#if money.credit_usd_cents > 0 && money.credit_from && money.credit_through}
							<div>
								<dt>
									Credit for unused days
									<span>{formatPeriod(money.credit_from, money.credit_through)}</span>
								</dt>
								<dd>−{formatUsd(money.credit_usd_cents)}</dd>
							</div>
						{/if}
						{#if money.new_charge}
							<div>
								<dt>
									New charge
									<span
										>{formatPeriod(
											money.new_charge.period_start,
											money.new_charge.period_end
										)}</span
									>
								</dt>
								<dd>{formatUsd(money.new_charge.amount_usd_cents)}</dd>
							</div>
							{#if money.credit_applied_usd_cents > 0}
								<div>
									<dt>Credit used on the new charge</dt>
									<dd>−{formatUsd(money.credit_applied_usd_cents)}</dd>
								</div>
							{/if}
							<div class="package-change__money-total">
								<dt>Left to pay</dt>
								<dd>{formatUsd(payNow)}</dd>
							</div>
							{#if leftoverCredit > 0}
								<div>
									<dt>Credit kept for later charges</dt>
									<dd>{formatUsd(leftoverCredit)}</dd>
								</div>
							{/if}
						{/if}
						{#each money.replaced_charges as charge (charge.id)}
							<div>
								<dt>
									Waiting charge cancelled
									<span>{formatPeriod(charge.period_start, charge.period_end)}</span>
								</dt>
								<dd class="package-change__struck">{formatUsd(charge.amount_usd_cents)}</dd>
							</div>
						{/each}
						{#if money.next_charge}
							<div>
								<dt>
									Replaced at the new price
									<span
										>{formatPeriod(
											money.next_charge.period_start,
											money.next_charge.period_end
										)}</span
									>
								</dt>
								<dd>{formatUsd(money.next_charge.amount_usd_cents)}</dd>
							</div>
						{/if}
					</dl>
					<p class="package-change__hint">
						{#if preview.timing === 'next_renewal'}
							Nothing changes until {formatCalendarDate(preview.effective_date)}. You can cancel the
							change until then.
						{:else if money.new_charge && intervalChanges}
							The new {preview.proposed.billing_interval === 'year' ? 'year' : 'month'} starts today.
							Paid-through moves only when you confirm the new charge's dates as paid.
						{:else if money.new_charge}
							The renewal date stays the same. Paid-through moves only when you confirm dates.
						{:else}
							No money changes: there is no paid period running today.
						{/if}
					</p>
				{/if}
			</section>

			<Textarea
				id="package-change-reason"
				label="Reason"
				bind:value={reason}
				rows={2}
				maxlength={500}
				invalid={Boolean(reasonError || fieldErrors.reason)}
				errorMessage={reasonError || fieldErrors.reason}
			/>
		{/if}

		{#if error}<p class="package-change__error" role="alert">{error}</p>{/if}
		{#if preview && preview.blockers.length && !error}
			<p class="package-change__error">
				This change can't go ahead yet. The warning above says what to fix first.
			</p>
		{/if}

		<div class="package-change__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Close</Button>
			<Button type="submit" loading={pending} disabled={!canConfirm}>
				{timing === 'next_renewal' ? 'Schedule change' : 'Change package now'}
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.package-change {
		display: grid;
		gap: var(--space-large);
	}
	.package-change p,
	.package-change h3,
	.package-change h4 {
		margin: 0;
	}
	.package-change__choices {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		align-items: end;
		gap: var(--space-base);
	}
	.package-change__choices > :global(:first-child) {
		grid-column: 1 / -1;
	}
	.package-change__loading {
		display: grid;
		gap: var(--space-base);
	}
	.package-change__hint,
	.package-change__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.package-change__note {
		display: block;
	}
	.package-change__blockers {
		margin: var(--space-smallest) 0 0;
		padding-left: var(--space-large);
	}
	.package-change__compare {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.package-change__side {
		display: grid;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.package-change__side--new {
		border-color: var(--color-interactive);
		background: var(--color-surface--background--subtle);
	}
	.package-change__side h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
	}
	.package-change__side p:last-child {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
	}
	.package-change__eyebrow {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	.package-change__block {
		display: grid;
		gap: var(--space-small);
	}
	.package-change__block h4 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.package-change__feature-groups {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.package-change__feature-groups > div {
		display: grid;
		align-content: start;
		gap: var(--space-small);
	}
	.package-change__features {
		display: grid;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.package-change__feature {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.package-change__feature > span:first-child {
		display: inline-grid;
		place-items: center;
		width: 20px;
		height: 20px;
		border-radius: var(--radius-circle, 50%);
	}
	.package-change__feature :global(svg) {
		width: 14px;
		height: 14px;
	}
	.package-change__feature--gained > span:first-child {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.package-change__feature--lost > span:first-child {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.package-change__feature em {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.package-change__table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--typography--fontSize-small);
	}
	.package-change__table th,
	.package-change__table td {
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: top;
	}
	.package-change__table thead th {
		color: var(--color-text--secondary);
		font-weight: 700;
	}
	.package-change__table tbody th {
		color: var(--color-heading);
	}
	.package-change__table .align-end {
		text-align: right;
		font-variant-numeric: tabular-nums;
	}
	.package-change__row--over td:last-child {
		color: var(--color-critical);
		font-weight: 700;
	}
	.package-change__money {
		display: grid;
		gap: 0;
		margin: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.package-change__money > div {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
	}
	.package-change__money > div + div {
		border-top: var(--border-base) solid var(--color-border);
	}
	.package-change__money dt span {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.package-change__money dd {
		margin: 0;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.package-change__money-total {
		background: var(--color-surface--background--subtle);
	}
	.package-change__money-total dt,
	.package-change__money-total dd {
		color: var(--color-heading);
		font-weight: 700;
	}
	.package-change__struck {
		color: var(--color-text--secondary);
		text-decoration: line-through;
	}
	.package-change__offer-choice {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		align-items: end;
		gap: var(--space-base);
	}
	.package-change__code {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);
	}
	.package-change__code > :global(:first-child) {
		flex: 1;
	}
	.package-change__offer {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.package-change__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.package-change__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 767px) {
		.package-change__choices,
		.package-change__offer-choice,
		.package-change__compare {
			grid-template-columns: 1fr;
		}
	}
</style>
