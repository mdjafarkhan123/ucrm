<script lang="ts">
	import { untrack } from 'svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import {
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { formatUsd, PackageApiError, type PackageSummary } from '$lib/jafar/packages';
	import {
		createPackageOffer,
		eligibilityLabels,
		formFromOffer,
		introPrice,
		savePackageOffer,
		type OfferForm,
		type PackageOffer
	} from '$lib/jafar/package-offers';
	import { offerLength } from '$lib/packages/public-package';

	// Package builder P11b: creates an introductory offer or edits one. Once a customer has claimed it, the
	// discount, billing, and length are fixed (plan § Prices and offers); everything else stays editable.
	// The parent mounts this fresh for each opening, so the fields and the idempotency key belong to it.
	let {
		offer = null,
		packages,
		onClose,
		onSaved
	}: {
		offer?: PackageOffer | null;
		packages: PackageSummary[];
		onClose: () => void;
		onSaved: (created: boolean) => void;
	} = $props();

	function localValue(iso: string) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(new Date(iso)));
	}

	const initial: OfferForm = untrack(() =>
		offer
			? formFromOffer(offer)
			: {
					name: '',
					apply_mode: 'automatic',
					code: null,
					discount_kind: 'percent',
					percent_off: null,
					amount_off_usd_cents: null,
					applies_to_monthly: true,
					applies_to_yearly: false,
					monthly_periods: 3,
					customer_eligibility: 'new',
					claim_starts_at: new Date().toISOString(),
					claim_ends_at: null,
					redemption_cap: null,
					package_ids: []
				}
	);
	const locked = untrack(() => offer?.terms_locked ?? false);
	const idempotencyKey = crypto.randomUUID();

	let form = $state<OfferForm>(initial);
	let startsAt = $state(localValue(initial.claim_starts_at));
	let hasEnd = $state(initial.claim_ends_at !== null);
	let endsAt = $state(
		localValue(
			initial.claim_ends_at ?? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
		)
	);
	let hasCap = $state(initial.redemption_cap !== null);
	let lengthChoice = $state(
		initial.monthly_periods === 3 || initial.monthly_periods === 6
			? String(initial.monthly_periods)
			: 'custom'
	);
	let percentText = $state<string | number | null>(initial.percent_off?.toString() ?? '');
	let amountCents = $state(initial.amount_off_usd_cents ?? 0);
	let monthsText = $state<string | number | null>(initial.monthly_periods?.toString() ?? '');
	let capText = $state<string | number | null>(initial.redemption_cap?.toString() ?? '');

	let pending = $state(false);
	let formError = $state('');
	let stale = $state(false);
	let fieldErrors = $state<Record<string, string>>({});

	// Published packages can take an offer; one already on the offer stays listed even if archived since.
	const choices = $derived(
		packages.filter(
			(pkg) => (pkg.published && !pkg.archived_at) || initial.package_ids.includes(pkg.id)
		)
	);

	// A number field can hand back a number or text; either way only a whole number counts.
	function wholeNumber(input: string | number | null) {
		const text = String(input ?? '').trim();
		const value = Number(text);
		return text && Number.isInteger(value) ? value : null;
	}

	const terms = $derived<OfferForm>({
		...form,
		code: form.apply_mode === 'code' ? (form.code ?? '').trim().toUpperCase() || null : null,
		percent_off: form.discount_kind === 'percent' ? wholeNumber(percentText) : null,
		amount_off_usd_cents: form.discount_kind === 'fixed' ? amountCents || null : null,
		monthly_periods: form.applies_to_monthly
			? lengthChoice === 'custom'
				? wholeNumber(monthsText)
				: Number(lengthChoice)
			: null,
		claim_starts_at: localDateTimeToIso(startsAt) ?? '',
		claim_ends_at: hasEnd ? (localDateTimeToIso(endsAt) ?? null) : null,
		redemption_cap: hasCap ? wholeNumber(capText) : null
	});

	const discountReady = $derived(
		terms.discount_kind === 'percent'
			? terms.percent_off !== null
			: terms.amount_off_usd_cents !== null
	);

	/** What each chosen package costs during and after the offer, on each billing it covers. */
	const previewLines = $derived(
		discountReady
			? choices
					.filter((pkg) => terms.package_ids.includes(pkg.id) && pkg.published)
					.flatMap((pkg) =>
						(['month', 'year'] as const)
							.filter((interval) =>
								interval === 'month' ? terms.applies_to_monthly : terms.applies_to_yearly
							)
							.map((interval) => {
								const normal =
									interval === 'month'
										? pkg.published!.monthly_price_usd_cents
										: pkg.published!.yearly_price_usd_cents;
								const per = interval === 'month' ? 'a month' : 'a year';
								const periods = interval === 'month' ? (terms.monthly_periods ?? 0) : 1;
								return {
									key: `${pkg.id}-${interval}`,
									name: pkg.published!.name,
									text:
										normal === null
											? `No ${interval === 'month' ? 'monthly' : 'yearly'} price, so the offer does not apply`
											: periods < 1
												? 'Choose how many months'
												: `${formatUsd(introPrice(terms, normal))} ${per} ${offerLength(interval, periods)}, then ${formatUsd(normal)} ${per}`
								};
							})
					)
			: []
	);

	function togglePackage(packageId: string, checked: boolean) {
		form.package_ids = checked
			? [...form.package_ids, packageId]
			: form.package_ids.filter((id) => id !== packageId);
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		pending = true;
		formError = '';
		stale = false;
		fieldErrors = {};
		try {
			if (offer) await savePackageOffer(offer.id, offer.revision, terms);
			else await createPackageOffer({ idempotency_key: idempotencyKey, terms });
			onSaved(!offer);
		} catch (error) {
			if (error instanceof PackageApiError && error.body.field_errors) {
				fieldErrors = error.body.field_errors;
				formError = error.message;
			} else {
				stale = error instanceof PackageApiError && error.body.reason === 'stale';
				formError = error instanceof Error ? error.message : 'The offer could not be saved.';
			}
		} finally {
			pending = false;
		}
	}
</script>

<Dialog
	open
	title={offer ? 'Edit offer' : 'New offer'}
	size="large"
	initialFocusId="offer-name"
	{onClose}
>
	<form class="offer-form" onsubmit={submit} novalidate>
		<Input
			id="offer-name"
			label="Offer name"
			required
			bind:value={form.name}
			invalid={Boolean(fieldErrors.name)}
			errorMessage={fieldErrors.name}
		/>

		<fieldset class="offer-form__group">
			<legend>Discount</legend>
			{#if locked}
				<p class="offer-form__hint">
					{offer?.claim_count}
					{offer?.claim_count === 1 ? 'customer has' : 'customers have'} claimed this offer, so its discount,
					billing, and length are fixed. Create a new offer to change them.
				</p>
			{/if}
			<div class="offer-form__row">
				<SegmentedControl
					label="Type"
					bind:value={
						() => form.discount_kind, (value) => (form.discount_kind = value as 'percent' | 'fixed')
					}
					disabled={locked}
					options={[
						{ value: 'percent', label: 'Percentage' },
						{ value: 'fixed', label: 'Fixed amount' }
					]}
				/>
				{#if form.discount_kind === 'percent'}
					<Input
						id="offer-percent"
						label="Percent off"
						type="number"
						required
						disabled={locked}
						bind:value={percentText}
						invalid={Boolean(fieldErrors.percent_off)}
						errorMessage={fieldErrors.percent_off}
					/>
				{:else}
					<MoneyInput
						id="offer-amount"
						label="Amount off (USD)"
						required
						disabled={locked}
						bind:value={amountCents}
						invalid={Boolean(fieldErrors.amount_off_usd_cents)}
						errorMessage={fieldErrors.amount_off_usd_cents}
					/>
				{/if}
			</div>
		</fieldset>

		<fieldset class="offer-form__group">
			<legend>Billing and length</legend>
			<Checkbox
				id="offer-monthly"
				label="Monthly billing"
				description="Discounts the first months in a row, starting with the first paid month."
				disabled={locked}
				bind:checked={form.applies_to_monthly}
				invalid={Boolean(fieldErrors.applies_to_monthly)}
			/>
			{#if form.applies_to_monthly}
				<div class="offer-form__row offer-form__indent">
					<SegmentedControl
						label="How many months"
						bind:value={lengthChoice}
						disabled={locked}
						options={[
							{ value: '3', label: '3 months' },
							{ value: '6', label: '6 months' },
							{ value: 'custom', label: 'Other' }
						]}
					/>
					{#if lengthChoice === 'custom'}
						<Input
							id="offer-months"
							label="Months (1 to 36)"
							type="number"
							required
							disabled={locked}
							bind:value={monthsText}
							invalid={Boolean(fieldErrors.monthly_periods)}
							errorMessage={fieldErrors.monthly_periods}
						/>
					{/if}
				</div>
			{/if}
			<Checkbox
				id="offer-yearly"
				label="Yearly billing"
				description="Discounts the first year only."
				disabled={locked}
				bind:checked={form.applies_to_yearly}
				invalid={Boolean(fieldErrors.applies_to_monthly)}
			/>
			{#if fieldErrors.applies_to_monthly}
				<p class="offer-form__error">{fieldErrors.applies_to_monthly}</p>
			{/if}
		</fieldset>

		<fieldset class="offer-form__group">
			<legend>Packages</legend>
			{#if choices.length === 0}
				<p class="offer-form__hint">Publish a package first. Offers apply to published packages.</p>
			{/if}
			{#each choices as pkg (pkg.id)}
				<Checkbox
					id={`offer-package-${pkg.id}`}
					label={(pkg.published ?? pkg.draft)?.name ?? pkg.slug}
					description={pkg.archived_at
						? 'Archived'
						: `${formatUsd(pkg.published?.monthly_price_usd_cents ?? null)} a month · ${formatUsd(pkg.published?.yearly_price_usd_cents ?? null)} a year${pkg.visibility === 'private' ? ' · private' : ''}`}
					checked={form.package_ids.includes(pkg.id)}
					onchange={(checked) => togglePackage(pkg.id, checked)}
				/>
			{/each}
			{#if fieldErrors.package_ids}<p class="offer-form__error">{fieldErrors.package_ids}</p>{/if}
		</fieldset>

		<fieldset class="offer-form__group">
			<legend>Who can claim it</legend>
			<div class="offer-form__row">
				<Select
					id="offer-eligibility"
					label="Customers"
					bind:value={
						() => form.customer_eligibility,
						(value) => (form.customer_eligibility = value as OfferForm['customer_eligibility'])
					}
					options={(['new', 'existing', 'any'] as const).map((value) => ({
						value,
						label: eligibilityLabels[value]
					}))}
				/>
				<SegmentedControl
					label="How it applies"
					bind:value={
						() => form.apply_mode, (value) => (form.apply_mode = value as 'automatic' | 'code')
					}
					options={[
						{ value: 'automatic', label: 'Automatically' },
						{ value: 'code', label: 'With a code' }
					]}
				/>
			</div>
			<p class="offer-form__hint">
				{form.apply_mode === 'automatic'
					? 'New customers see it on the package cards and get it when you activate them. You choose it for an existing customer in Change package.'
					: 'Not shown publicly. You type the code when you activate a customer or change their package.'}
			</p>
			{#if form.apply_mode === 'code'}
				<Input
					id="offer-code"
					label="Code"
					required
					bind:value={() => form.code ?? '', (value) => (form.code = String(value).toUpperCase())}
					invalid={Boolean(fieldErrors.code)}
					errorMessage={fieldErrors.code}
				/>
			{/if}
		</fieldset>

		<fieldset class="offer-form__group">
			<legend>Claim window</legend>
			<DateTimePicker
				id="offer-starts"
				dateLabel="Claims open"
				timeLabel="Opening time"
				required
				value={dateTimePickerValueFromLocalString(startsAt)}
				onchange={(value: DateTimePickerValue) =>
					(startsAt = dateTimePickerValueToLocalString(value))}
				invalid={Boolean(fieldErrors.claim_starts_at)}
				errorMessage={fieldErrors.claim_starts_at}
			/>
			<Toggle
				id="offer-has-end"
				label="Stop new claims on a date"
				description="Customers who already claimed it keep all their discounted months."
				bind:checked={hasEnd}
			/>
			{#if hasEnd}
				<DateTimePicker
					id="offer-ends"
					dateLabel="Claims close"
					timeLabel="Closing time"
					required
					value={dateTimePickerValueFromLocalString(endsAt)}
					onchange={(value: DateTimePickerValue) =>
						(endsAt = dateTimePickerValueToLocalString(value))}
					invalid={Boolean(fieldErrors.claim_ends_at)}
					errorMessage={fieldErrors.claim_ends_at}
				/>
			{/if}
			<Toggle
				id="offer-has-cap"
				label="Limit how many customers can claim it"
				bind:checked={hasCap}
			/>
			{#if hasCap}
				<Input
					id="offer-cap"
					label="Most customers"
					type="number"
					required
					bind:value={capText}
					invalid={Boolean(fieldErrors.redemption_cap)}
					errorMessage={fieldErrors.redemption_cap}
				/>
			{/if}
		</fieldset>

		{#if previewLines.length}
			<section class="offer-form__preview" aria-labelledby="offer-preview-heading">
				<h3 id="offer-preview-heading">What customers pay</h3>
				<ul>
					{#each previewLines as line (line.key)}
						<li><strong>{line.name}</strong> {line.text}</li>
					{/each}
				</ul>
			</section>
		{/if}

		{#if formError}
			<Banner type="error">
				{formError}
				{#if stale}Close this and open the offer again to see the latest version.{/if}
			</Banner>
		{/if}
		<div class="offer-form__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending} disabled={stale}
				>{offer ? 'Save offer' : 'Create offer'}</Button
			>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.offer-form {
		display: grid;
		gap: var(--space-large);

		&__group {
			display: grid;
			gap: var(--space-base);
			min-width: 0;
			margin: 0;
			padding: 0;
			border: 0;

			legend {
				margin-bottom: var(--space-small);
				padding: 0;
				color: var(--color-heading);
				font-weight: 600;
			}
		}

		&__row {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
			align-items: end;
			gap: var(--space-base);
		}

		&__indent {
			padding-left: var(--space-large);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__preview {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}

			ul {
				display: grid;
				gap: var(--space-smaller);
				margin: 0;
				padding: 0;
				list-style: none;
				font-size: var(--typography--fontSize-small);
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
