<script lang="ts">
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { getLocalTimeZone, today, type CalendarDate } from '@internationalized/date';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		fetchPriceList,
		margin,
		picturesOffered,
		priceListKey,
		priceMoved,
		textingSetupKey,
		textPrice,
		type PriceListRow
	} from '$lib/jafar/texting-setup';
	import dollarIcon from '@tabler/icons/outline/currency-dollar.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import boltIcon from '@tabler/icons/outline/bolt.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';

	// Change price (`concept.pen` `dc8G7`): Twilio's costs at the top, the new prices with the margin worked out as
	// you type, and when they start. Review price and Set price open it on a row; Add a country opens it empty, asks
	// Twilio for the picked country's costs, then carries on as that country's Change price.
	let {
		row: startRow,
		listed,
		onClose
	}: {
		/** The country being priced; null for Add a country. */
		row: PriceListRow | null;
		/** Countries already on the list, left out of Add a country's picker. */
		listed: string[];
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let row = $state<PriceListRow | null>(untrack(() => startRow));
	let picking = $state('');
	let asking = $state(false);
	let saving = $state(false);
	let error = $state('');

	const country = $derived(row ? countryDisplayName(row.country) : '');
	const pictures = $derived(row ? picturesOffered(row) : false);

	// Prices count in ten-thousandths of a dollar (texts) or cents (numbers), the units MoneyInput binds.
	const toUnits = (amount: number | undefined | null, scale: number) =>
		amount ? Math.round(amount * scale) : 0;
	let segment = $state(0);
	let mms = $state(0);
	let monthly = $state(0);

	function fill(next: PriceListRow) {
		row = next;
		segment = toUnits(next.price.segment?.rate, 10_000);
		mms = toUnits(next.price.mms?.rate, 10_000);
		monthly = toUnits(next.number?.monthly, 100);
	}
	untrack(() => {
		if (startRow) fill(startRow);
	});

	let starts = $state<'now' | 'date'>('now');
	const tomorrow = today(getLocalTimeZone()).add({ days: 1 });
	let startDate = $state<CalendarDate>(tomorrow);
	const startLabel = $derived(
		new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(
			startDate.toDate(getLocalTimeZone())
		)
	);

	function marginHint(units: number, scale: number, cost: number | null | undefined) {
		if (!units || cost === null || cost === undefined)
			return { text: '', back: false, loss: false };
		const rate = units / scale;
		const now = `Margin ${margin(rate, cost)}`;
		const loss = rate < cost;
		const segmentTwilio = row?.twilio.segment;
		if (
			scale === 10_000 &&
			row &&
			priceMoved(row) &&
			segmentTwilio?.previous &&
			row.price.segment
		) {
			const before = margin(row.price.segment.rate, segmentTwilio.previous);
			if (Number.parseInt(margin(rate, cost)) >= Number.parseInt(before)) {
				return { text: `${now}, back where it was`, back: true, loss };
			}
		}
		return { text: now, back: false, loss };
	}
	const segmentHint = $derived(marginHint(segment, 10_000, row?.twilio.segment?.cost));
	const monthlyHint = $derived(marginHint(monthly, 100, row?.twilio.number_month?.cost));

	const usedBy = $derived.by(() => {
		if (!row) return 'For every business';
		if (row.using)
			return `For every business · ${row.using} ${row.using === 1 ? 'uses' : 'use'} it now`;
		if (row.asked) return `For every business · ${row.asked} asked for it`;
		return 'For every business';
	});

	const keepLine = $derived.by(() => {
		if (!row?.price.segment) {
			return `Businesses can text ${country} once it has a price and Uplift turns it on for them.`;
		}
		const old = textPrice(row.price.segment.rate);
		return starts === 'date'
			? `Businesses see the new price before they send. Texts sent before ${startLabel} keep ${old}.`
			: `Businesses see the new price before they send. Texts already sent keep ${old}.`;
	});

	async function pickCountry(code: string) {
		picking = code;
		if (!code) return;
		asking = true;
		error = '';
		try {
			const response = await fetch('/api/jafar/texting-setup/prices/check', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ country: code })
			});
			const body = await response.json().catch(() => ({}));
			if (!response.ok) {
				error = body.error ?? 'Twilio could not be asked just now. Try again.';
				return;
			}
			const list = await queryClient.fetchQuery({
				queryKey: priceListKey,
				queryFn: fetchPriceList,
				staleTime: 0
			});
			const found = list.countries.find((item) => item.country === code);
			if (!found) {
				error = `Twilio has no prices for ${countryDisplayName(code)}. Pick another country.`;
				return;
			}
			fill(found);
		} catch {
			error = 'Check your connection. Nothing was changed.';
		} finally {
			asking = false;
		}
	}

	function changed(units: number, scale: number, current: number | null | undefined) {
		if (!units) return null;
		return toUnits(current, scale) === units ? null : units / scale;
	}

	async function save() {
		if (!row) return;
		if (!segment) {
			error = `Type what businesses pay a segment to ${country}.`;
			return;
		}
		const input = {
			country: row.country,
			segment: changed(segment, 10_000, row.price.segment?.rate),
			mms: pictures ? changed(mms, 10_000, row.price.mms?.rate) : null,
			number_month: changed(monthly, 100, row.number?.monthly),
			starts: starts === 'date' ? startDate.toDate(getLocalTimeZone()).toISOString() : null
		};
		if (input.segment === null && input.mms === null && input.number_month === null) {
			error = 'Change a price first, or press Cancel.';
			return;
		}
		saving = true;
		error = '';
		try {
			const response = await fetch('/api/jafar/texting-setup/prices', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const body = await response.json().catch(() => ({}));
			if (!response.ok) {
				error = body.error ?? 'The price could not be saved.';
				return;
			}
			await queryClient.invalidateQueries({ queryKey: textingSetupKey });
			toast.success(
				`${country} price saved`,
				starts === 'date' ? `It starts on ${startLabel}.` : 'Businesses see it straight away.'
			);
			onClose();
		} catch {
			error = 'Check your connection. Nothing was changed.';
		} finally {
			saving = false;
		}
	}
</script>

{#snippet flag()}
	{#if row}<PaperworkFlag code={row.country} size={40} />{/if}
{/snippet}

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	open
	width={640}
	title={row ? `${row.price.segment ? 'Change' : 'Set'} the ${country} price` : 'Add a country'}
	subtitle={row ? usedBy : 'Pick a country, then its prices. They are the same for every business.'}
	icon={dollarIcon}
	iconTone="conversation"
	lead={row ? flag : undefined}
	closeDisabled={saving}
	initialFocusId={row ? 'price-segment' : 'price-country'}
	{onClose}
>
	<div class="change-price">
		{#if error}<FormErrorSummary message={error} hint="Nothing was changed." />{/if}

		{#if !row}
			<CountryPicker
				id="price-country"
				label="Country"
				required
				except={listed}
				value={picking}
				onchange={pickCountry}
				disabled={asking}
			/>
			{#if asking}
				<p class="change-price__asking" aria-live="polite">Asking Twilio for its prices…</p>
			{/if}
		{:else}
			<dl class="change-price__twilio">
				<div>
					<dt>Twilio, a segment</dt>
					<dd>
						{#if row.twilio.segment}
							{textPrice(
								row.twilio.segment.cost
							)}{#if priceMoved(row) && row.twilio.segment.previous !== null}
								<span> · was {textPrice(row.twilio.segment.previous)}</span>{/if}
						{:else}
							<span>Not checked yet</span>
						{/if}
					</dd>
				</div>
				<div>
					<dt>Twilio, a number a month</dt>
					<dd>
						{#if row.twilio.number_month}
							${row.twilio.number_month.cost.toFixed(2)}
						{:else if row.twilio.segment}
							<span>None to rent</span>
						{:else}
							<span>Not checked yet</span>
						{/if}
					</dd>
				</div>
				<div>
					<dt>Picture texts</dt>
					<dd>
						{#if pictures}Offered{:else}<span>Not offered there</span>{/if}
					</dd>
				</div>
			</dl>

			<div class="change-price__boxes">
				<div class="change-price__box">
					<MoneyInput
						id="price-segment"
						label="They pay a segment"
						required
						decimals={4}
						placeholder="0.00"
						bind:value={segment}
						disabled={saving}
						currencyCode="USD"
					/>
					{#if segmentHint.text}
						<p
							class="change-price__hint"
							class:change-price__hint--back={segmentHint.back}
							class:change-price__hint--loss={segmentHint.loss}
						>
							{segmentHint.text}
						</p>
					{/if}
				</div>
				<div class="change-price__box">
					<MoneyInput
						id="price-number"
						label="They pay a number a month"
						bind:value={monthly}
						disabled={saving}
						currencyCode="USD"
					/>
					{#if monthlyHint.text}<p
							class="change-price__hint"
							class:change-price__hint--loss={monthlyHint.loss}
						>
							{monthlyHint.text}
						</p>{/if}
				</div>
				{#if pictures}
					<div class="change-price__box">
						<MoneyInput
							id="price-picture"
							label="They pay a picture text"
							decimals={4}
							bind:value={mms}
							disabled={saving}
							currencyCode="USD"
						/>
					</div>
				{/if}
			</div>

			<div class="change-price__starts">
				<SegmentedControl
					label="Starts"
					name="price-starts"
					value={starts}
					options={[
						{ value: 'now', label: 'Now', icon: boltIcon },
						{ value: 'date', label: 'On a date', icon: calendarIcon }
					]}
					onchange={(value) => (starts = value as 'now' | 'date')}
					disabled={saving}
				/>
				{#if starts === 'date'}
					<div class="change-price__date">
						<CalendarPicker
							id="price-start-date"
							label="Start date"
							hideLabel
							value={startDate}
							minValue={tomorrow}
							onchange={(value) => {
								if (value) startDate = value;
							}}
							disabled={saving}
						/>
					</div>
				{/if}
			</div>

			<Banner type="notice">{keepLine}</Banner>
		{/if}
	</div>
	{#snippet footer()}
		<Button variant="secondary" onclick={onClose} disabled={saving}>Cancel</Button>
		<Button onclick={save} loading={saving} disabled={!row || asking}>
			{#if !saving}<span aria-hidden="true">{@html checkIcon}</span>{/if}
			{saving ? 'Saving…' : 'Save price'}
		</Button>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.change-price {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__asking {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__twilio {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-large);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}

			dd {
				margin: 2px 0 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;

				span {
					color: var(--color-text--secondary);
					font-weight: 500;
				}
			}
		}

		&__boxes {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__box {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			&--back {
				color: var(--color-success--onSurface);
				font-weight: 600;
			}

			&--loss {
				color: var(--color-critical);
				font-weight: 600;
			}
		}

		&__starts {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			gap: var(--space-slim);
		}

		&__date {
			width: calc(var(--base-unit) * 11);
		}
	}
</style>
