<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import ChangePriceDialog from '$lib/components/jafar/texting-setup/ChangePriceDialog.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		fetchPriceList,
		margin,
		numberKindLabel,
		numberPrice,
		picturesOffered,
		priceListKey,
		priceMoved,
		priceStatus,
		textingSetupKey,
		textPrice,
		whenAsked,
		type PriceListRow
	} from '$lib/jafar/texting-setup';
	import dollarIcon from '@tabler/icons/outline/currency-dollar.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trendingDownIcon from '@tabler/icons/outline/trending-down.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import circleOffIcon from '@tabler/icons/outline/circle-off.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';

	// Countries & prices tab of Texting setup (`concept.pen` `R6mF2`): one price list for every business, with what
	// Twilio charges Uplift beside what businesses pay. Replaces the old "SMS retail rates" list.
	const queryClient = useQueryClient();
	const toast = getToastManager();
	const list = createQuery(() => ({ queryKey: priceListKey, queryFn: fetchPriceList }));

	const rows = $derived(list.data?.countries ?? []);
	let search = $state('');
	const shown = $derived.by(() => {
		const term = search.trim().toLowerCase();
		const named = rows.map((row) => ({ row, name: countryDisplayName(row.country) }));
		return named
			.filter(
				({ name, row }) =>
					!term || name.toLowerCase().includes(term) || row.country.toLowerCase() === term
			)
			.sort((a, b) => a.name.localeCompare(b.name));
	});
	const live = $derived(rows.filter((row) => priceStatus(row).label === 'Live').length);
	const hint = $derived(
		list.isPending
			? 'Loading…'
			: `${rows.length} ${rows.length === 1 ? 'country' : 'countries'} · ${live} live · the same prices for every business`
	);

	const moved = $derived(
		rows
			.filter(priceMoved)
			.sort((a, b) =>
				(b.twilio.segment?.changed_at ?? '').localeCompare(a.twilio.segment?.changed_at ?? '')
			)
	);
	const movedLine = $derived.by(() => {
		const row = moved[0];
		const twilio = row?.twilio.segment;
		if (!row || !twilio || twilio.previous === null) return '';
		const name = countryDisplayName(row.country);
		const day = whenAsked(twilio.changed_at!);
		let line = `Twilio raised its ${name} price ${day === 'today' || day === 'yesterday' ? day : `on ${day}`}, from ${textPrice(twilio.previous)} to ${textPrice(twilio.cost)} a segment.`;
		if (row.price.segment) {
			line += ` Your margin there fell from ${margin(row.price.segment.rate, twilio.previous)} to ${margin(row.price.segment.rate, twilio.cost)}.`;
		}
		if (moved.length > 1)
			line += ` ${moved.length - 1} more ${moved.length === 2 ? 'country' : 'countries'} moved too.`;
		return line;
	});

	let editing = $state<{ row: PriceListRow | null } | null>(null);
	let checking = $state(false);

	async function checkTwilio() {
		checking = true;
		try {
			const response = await fetch('/api/jafar/texting-setup/prices/check', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: '{}'
			});
			const body = await response.json().catch(() => ({}));
			if (!response.ok) {
				toast.error('Couldn’t ask Twilio', body.error ?? 'Try again in a minute.');
				return;
			}
			await queryClient.invalidateQueries({ queryKey: priceListKey });
			const failed: string[] = body.failed ?? [];
			if (failed.length) {
				toast.error(
					'Some prices didn’t come back',
					`Twilio didn’t answer for ${failed.map(countryDisplayName).join(', ')}. Try again later.`
				);
			} else {
				toast.success(
					'Twilio prices are up to date',
					`Checked ${body.checked?.length ?? 0} countries.`
				);
			}
		} catch {
			toast.error('Couldn’t ask Twilio', 'Check your connection and try again.');
		} finally {
			checking = false;
		}
	}

	let stopping = $state<PriceListRow | null>(null);
	let switching = $state(false);

	async function setOffered(row: PriceListRow, offered: boolean) {
		switching = true;
		try {
			const response = await fetch(`/api/jafar/texting-setup/prices/${row.country}/offered`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ offered })
			});
			const body = await response.json().catch(() => ({}));
			if (!response.ok) {
				toast.error('Nothing was changed', body.error ?? 'Try again.');
				return;
			}
			stopping = null;
			const name = countryDisplayName(row.country);
			toast.success(offered ? `${name} is offered again` : `${name} is no longer offered`);
			await queryClient.invalidateQueries({ queryKey: textingSetupKey });
		} catch {
			toast.error('Nothing was changed', 'Check your connection and try again.');
		} finally {
			switching = false;
		}
	}

	function usingLabel(row: PriceListRow) {
		if (row.using) return String(row.using);
		if (row.asked) return `${row.asked} asked`;
		return '0';
	}

	function laterLabel(row: PriceListRow) {
		if (!row.later) return '';
		const day = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(
			new Date(row.later.from)
		);
		return `${textPrice(row.later.segment)} from ${day}`;
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="prices" aria-labelledby="prices-title">
	<CardHeader
		id="prices-title"
		title="Countries & prices"
		{hint}
		icon={dollarIcon}
		tone="conversation"
	>
		{#snippet actions()}
			<SearchInput
				id="prices-search"
				ariaLabel="Find a country"
				placeholder="Find a country"
				size="compact"
				class="prices__search"
				bind:value={search}
			/>
			<Button variant="secondary" onclick={checkTwilio} loading={checking}>
				{#if !checking}<span aria-hidden="true">{@html refreshIcon}</span>{/if}
				{checking ? 'Checking…' : 'Check Twilio prices'}
			</Button>
			<Button onclick={() => (editing = { row: null })}>
				<span aria-hidden="true">{@html plusIcon}</span>
				Add a country
			</Button>
		{/snippet}
	</CardHeader>

	{#if list.isPending}
		<div class="prices__skeleton" aria-busy="true" aria-label="Loading prices">
			{#each [140, 110, 150, 120] as width (width)}
				<div class="prices__skeleton-row">
					<span class="prices__skeleton-dot"></span>
					<span class="prices__skeleton-lines">
						<span style:width={`${width}px`}></span>
						<span style:width={`${width - 50}px`}></span>
					</span>
					<span class="prices__skeleton-pill"></span>
				</div>
			{/each}
		</div>
	{:else if list.isError}
		<ErrorState
			title="Couldn’t load prices"
			description="Nothing was changed."
			retry={() => list.refetch()}
		/>
	{:else if rows.length === 0}
		<EmptyState
			title="No countries yet"
			description="Add a country and its price before any business can text there."
			icon={worldIcon}
			tone="conversation"
		>
			{#snippet action()}
				<Button onclick={() => (editing = { row: null })}>
					<span aria-hidden="true">{@html plusIcon}</span>
					Add a country
				</Button>
			{/snippet}
		</EmptyState>
	{:else}
		{#if movedLine}
			<div class="prices__notice">
				<Banner type="warning">
					{movedLine}
					{#snippet action()}
						<Button variant="secondary" size="small" onclick={() => (editing = { row: moved[0] })}>
							Review price
						</Button>
					{/snippet}
				</Banner>
			</div>
		{/if}

		<div class="prices__table" role="table" aria-label="Countries and prices">
			<div class="prices__head" role="row">
				<span role="columnheader">Country</span>
				<span role="columnheader">Twilio cost</span>
				<span role="columnheader">They pay</span>
				<span role="columnheader">Margin</span>
				<span role="columnheader">Picture</span>
				<span role="columnheader">Number a month</span>
				<span role="columnheader">Using it</span>
				<span role="columnheader">Status</span>
				<span role="columnheader"><span class="prices__hidden">Actions</span></span>
			</div>
			{#each shown as { row, name } (row.country)}
				{@const status = priceStatus(row)}
				{@const fell = priceMoved(row)}
				{@const loss =
					!!row.price.segment &&
					!!row.twilio.segment &&
					row.price.segment.rate < row.twilio.segment.cost}
				<div class="prices__row" role="row">
					<span class="prices__country" role="cell">
						<PaperworkFlag code={row.country} />
						<span class="prices__stack">
							<strong>{name}</strong>
							<span>{numberKindLabel(row)}</span>
						</span>
					</span>
					<span class="prices__cost" role="cell">
						{#if row.twilio.segment}
							{textPrice(row.twilio.segment.cost)} a segment{#if row.country === 'US'}<br /><span
									>+ carrier fee</span
								>{/if}
						{:else}
							<span class="prices__quiet">Not checked</span>
						{/if}
					</span>
					<span class="prices__stack" role="cell">
						{#if row.price.segment}
							<span class="prices__price"
								><strong>{textPrice(row.price.segment.rate)}</strong> a segment</span
							>
						{:else}
							<span>
								<Button variant="secondary" size="small" onclick={() => (editing = { row })}>
									Set price
								</Button>
							</span>
						{/if}
						{#if row.later}
							<span class="prices__later">
								<span aria-hidden="true">{@html calendarIcon}</span>
								{laterLabel(row)}
							</span>
						{/if}
					</span>
					<span
						class="prices__margin"
						class:prices__margin--fell={fell}
						class:prices__margin--loss={loss}
						role="cell"
					>
						{#if row.price.segment && row.twilio.segment}
							{#if fell}<span aria-hidden="true">{@html trendingDownIcon}</span>{/if}
							{margin(row.price.segment.rate, row.twilio.segment.cost)}
						{:else}
							<span class="prices__quiet">—</span>
						{/if}
					</span>
					<span class="prices__plain" role="cell">
						{#if !picturesOffered(row)}
							<span class="prices__quiet">Not offered</span>
						{:else if row.price.mms}
							{textPrice(row.price.mms.rate)} each
						{:else}
							<span class="prices__quiet">No price</span>
						{/if}
					</span>
					<span class="prices__plain" role="cell">
						{numberPrice(row.number) ?? '—'}
					</span>
					<span class="prices__using" role="cell">{usingLabel(row)}</span>
					<span role="cell"><StatusBadge status={status.tone}>{status.label}</StatusBadge></span>
					<span class="prices__action" role="cell">
						<DropdownMenu
							triggerLabel={`More for ${name}`}
							items={[
								{
									label: row.price.segment ? 'Change price' : 'Set a price',
									icon: pencilIcon,
									onSelect: () => (editing = { row })
								}
							]}
							footer={row.offered
								? [
										{
											label: `Stop offering ${name}`,
											icon: circleOffIcon,
											destructive: true,
											onSelect: () => (stopping = row)
										}
									]
								: [
										{
											label: `Offer ${name} again`,
											icon: circleCheckIcon,
											onSelect: () => setOffered(row, true)
										}
									]}
						/>
					</span>
				</div>
			{:else}
				<p class="prices__line">No country matches “{search.trim()}”.</p>
			{/each}
		</div>

		<p class="prices__foot">
			<span aria-hidden="true">{@html infoIcon}</span>
			A new price starts now or on a date you pick. Texts already sent keep the price they were sent at.
			Businesses see these prices before they send or buy.
		</p>
	{/if}
</section>

{#if editing}
	<ChangePriceDialog
		row={editing.row}
		listed={rows.map((row) => row.country)}
		onClose={() => (editing = null)}
	/>
{/if}

{#if stopping}
	{@const name = countryDisplayName(stopping.country)}
	{@const row = stopping}
	<ConfirmDialog
		open
		title={`Stop offering ${name}?`}
		icon={circleOffIcon}
		tone="critical"
		confirmLabel="Stop offering"
		destructive
		loading={switching}
		onConfirm={() => setOffered(row, false)}
		onClose={() => {
			if (!switching) stopping = null;
		}}
	>
		<p class="prices__confirm">
			Businesses can’t ask for {name} from now on.
			{#if row.using}
				The {row.using}
				{row.using === 1 ? 'business' : 'businesses'} already texting there keep it until you turn it
				off on each business’s page.
			{/if}
		</p>
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.prices {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		:global(.prices__search) {
			width: 240px;
		}

		&__notice {
			padding: 0 var(--space-medium) var(--space-base);
		}

		&__head,
		&__row {
			display: grid;
			grid-template-columns:
				minmax(0, 1.5fr) minmax(0, 1.1fr) minmax(0, 1fr) 80px minmax(0, 0.8fr)
				minmax(0, 1.1fr) 80px 110px 40px;
			align-items: center;
			column-gap: var(--space-slim);
		}

		&__head {
			padding: 10px var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__row {
			padding: 14px var(--space-medium);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__country {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			min-width: 0;
		}

		&__stack {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			> span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}

		&__cost,
		&__plain {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__price {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
			}
		}

		&__stack > &__later {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			height: 24px;
			margin-top: var(--space-smaller);
			padding: 0 var(--space-small);
			border-radius: var(--radius-circle);
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);
			font-weight: 600;

			span {
				display: inline-flex;
				width: 12px;
				height: 12px;
			}
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0, 0, 0, 0);
			white-space: nowrap;
		}

		&__margin {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&--fell {
				color: var(--color-warning--onSurface);
			}

			&--loss {
				color: var(--color-critical);
			}

			span[aria-hidden] {
				display: inline-flex;
				width: 14px;
				height: 14px;
			}
		}

		&__using {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__quiet {
			color: var(--color-text--secondary);
			font-weight: 500;
		}

		&__action {
			display: flex;
			justify-content: flex-end;
		}

		&__line {
			margin: 0;
			padding: 14px var(--space-medium);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__foot {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			span {
				display: inline-flex;
				flex: none;
				width: 14px;
				height: 14px;
				color: var(--color-informative);
			}
		}

		&__confirm {
			margin: 0;
		}

		&__skeleton {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__skeleton-row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__skeleton-dot {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
		}

		&__skeleton-lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);

			span {
				height: 10px;
				border-radius: var(--radius-small);
				background: var(--color-surface--background);
			}
		}

		&__skeleton-pill {
			width: 56px;
			height: 22px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
		}
	}
</style>
