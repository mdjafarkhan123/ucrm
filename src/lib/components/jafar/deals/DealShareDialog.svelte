<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate, today, getLocalTimeZone } from '@internationalized/date';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString } from '$lib/components/ui/date-time';
	import { formatUsd } from '$lib/jafar/packages';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		SHARED_PACKAGES_MAX,
		dealPackagesKey,
		fetchDealPackages,
		refreshDeals,
		suggestedNextStep
	} from '$lib/jafar/deals';

	// Jafar business management B4: "Pricing shared". Jafar picks the packages he sent (the first is the main one),
	// copies their pricing-page links, and saves. The server copies each package's price and offers from the
	// pricing page at that moment, so the Deal keeps what the business saw (B4 Q4). The follow-up is prefilled
	// three days on.
	let {
		dealId,
		relationshipId,
		businessName,
		onDone,
		onClose
	}: {
		dealId: string;
		relationshipId: string;
		businessName: string;
		onDone?: () => void;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const packages = createQuery(() => ({
		queryKey: dealPackagesKey,
		queryFn: fetchDealPackages,
		staleTime: 60_000
	}));

	let chosen = $state<string[]>([]);
	let billing = $state<string>('month');
	const suggestion = suggestedNextStep('pricing_shared', businessName);
	let text = $state(suggestion.text);
	let dueOn = $state<CalendarDate | undefined>(calendarDateFromString(suggestion.due_on));
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let copied = $state<string | null>(null);

	const todayDate = today(getLocalTimeZone());
	const offersYearly = $derived(
		(packages.data ?? []).some((pkg) => pkg.yearly_price_usd_cents !== null)
	);

	function toggle(slug: string) {
		if (chosen.includes(slug)) chosen = chosen.filter((item) => item !== slug);
		else if (chosen.length < SHARED_PACKAGES_MAX) chosen = [...chosen, slug];
	}

	function linkFor(slug: string, yearly: boolean) {
		const url = new URL(`/packages/${slug}`, window.location.origin);
		if (billing === 'year' && yearly) url.searchParams.set('billing', 'year');
		return url.toString();
	}

	async function copy(slug: string, yearly: boolean) {
		try {
			await navigator.clipboard.writeText(linkFor(slug, yearly));
			copied = slug;
			setTimeout(() => {
				if (copied === slug) copied = null;
			}, 2000);
		} catch {
			toast.error('The link could not be copied. Select it and copy it yourself.');
		}
	}

	function priceLine(monthly: number | null, yearly: number | null) {
		const parts = [];
		if (monthly !== null) parts.push(`${formatUsd(monthly)} a month`);
		if (yearly !== null) parts.push(`${formatUsd(yearly)} a year`);
		return parts.join(' · ');
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		formError = '';
		const errors: Record<string, string> = {};
		if (!chosen.length) errors.package_slugs = 'Choose the package you shared.';
		if (!text.trim()) errors['follow_up.text'] = 'Say what the follow-up is.';
		if (!dueOn) errors['follow_up.due_on'] = 'Choose when to follow up.';
		fieldErrors = errors;
		if (Object.keys(errors).length) return;

		saving = true;
		const result = await sendLeadWrite(
			`/api/jafar/deals/${encodeURIComponent(dealId)}/pricing`,
			'POST',
			{
				package_slugs: chosen,
				billing: billing === 'year' ? 'year' : 'month',
				follow_up: { text: text.trim(), due_on: dueOn!.toString() }
			}
		);
		saving = false;
		if (!result.ok) {
			fieldErrors = result.fieldErrors;
			formError = result.error;
			if (result.fieldErrors.package_slugs) void packages.refetch();
			return;
		}
		await refreshDeals(queryClient, relationshipId);
		toast.success('Pricing shared saved');
		onDone?.();
		onClose();
	}
</script>

<Dialog open={true} title="Pricing shared" {onClose}>
	<form class="deal-share" onsubmit={submit} novalidate>
		<fieldset class="deal-share__group">
			<legend>Which packages did you share?</legend>
			<p class="deal-share__hint">
				The price and any intro offer are saved as the pricing page shows them today. The first one
				you tick is the main package.
			</p>

			{#if packages.isPending}
				<LoadingSkeleton variant="table" rows={3} label="Loading packages" />
			{:else if packages.isError}
				<p class="deal-share__error" role="alert">{packages.error.message}</p>
			{:else if !packages.data.length}
				<p class="deal-share__hint">No package is on the pricing page right now.</p>
			{:else}
				{#if offersYearly}
					<SegmentedControl
						ariaLabel="Billing in the link"
						size="small"
						options={[
							{ value: 'month', label: 'Monthly' },
							{ value: 'year', label: 'Yearly' }
						]}
						bind:value={billing}
					/>
				{/if}

				<ul class="deal-share__packages">
					{#each packages.data as pkg (pkg.slug)}
						{@const order = chosen.indexOf(pkg.slug)}
						<li class={['deal-share__package', order >= 0 && 'deal-share__package--chosen']}>
							<label class="deal-share__choice">
								<input
									type="checkbox"
									checked={order >= 0}
									disabled={order < 0 && chosen.length >= SHARED_PACKAGES_MAX}
									onchange={() => toggle(pkg.slug)}
								/>
								<span class="deal-share__name">
									{pkg.name}
									{#if order === 0 && chosen.length > 1}<small>Main</small>{/if}
								</span>
								<span class="deal-share__price">
									{priceLine(pkg.monthly_price_usd_cents, pkg.yearly_price_usd_cents)}
								</span>
							</label>
							{#if order >= 0}
								<button
									type="button"
									class="deal-share__copy"
									onclick={() => copy(pkg.slug, pkg.yearly_price_usd_cents !== null)}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a bundled Tabler icon. -->
									<span aria-hidden="true">{@html copied === pkg.slug ? checkIcon : copyIcon}</span>
									{copied === pkg.slug ? 'Copied' : 'Copy link'}
								</button>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
			{#if fieldErrors.package_slugs}
				<p class="deal-share__error" role="alert">{fieldErrors.package_slugs}</p>
			{/if}
		</fieldset>

		<Input
			id="deal-share-follow-up"
			label="Follow-up"
			maxlength={200}
			required
			autocomplete="off"
			invalid={Boolean(fieldErrors['follow_up.text'])}
			errorMessage={fieldErrors['follow_up.text'] ?? ''}
			bind:value={text}
		/>
		<CalendarPicker
			id="deal-share-due"
			label="Follow up on"
			required
			minValue={todayDate}
			invalid={Boolean(fieldErrors['follow_up.due_on'])}
			errorMessage={fieldErrors['follow_up.due_on'] ?? ''}
			bind:value={dueOn}
		/>

		{#if formError && !Object.keys(fieldErrors).some((key) => key !== 'form')}
			<p class="deal-share__error" role="alert">{formError}</p>
		{/if}

		<div class="deal-share__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button type="submit" variant="primary" loading={saving}>Save</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.deal-share {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			margin: 0;
			padding: 0;
			border: 0;

			legend {
				margin-bottom: var(--space-smaller);
				color: var(--color-text);
				font-weight: 600;
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__packages {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__package {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			transition: border-color var(--timing-quick);

			&:hover {
				border-color: var(--color-border--interactive, var(--color-interactive));
			}
		}

		&__package--chosen {
			border-color: var(--color-brand);
			background: var(--color-surface--active);
		}

		&__choice {
			display: grid;
			grid-template-columns: auto minmax(0, 1fr);
			column-gap: var(--space-slim);
			flex: 1;
			min-width: 0;
			cursor: pointer;

			input {
				grid-row: span 2;
				align-self: center;
				width: 18px;
				height: 18px;
				accent-color: var(--color-brand);
			}
		}

		&__name {
			color: var(--color-heading);
			font-weight: 600;

			small {
				margin-left: var(--space-smaller);
				padding: 0 var(--space-small);
				border-radius: var(--radius-circle);
				color: var(--color-informative--onSurface);
				background: var(--color-informative--surface);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__price {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;
		}

		&__copy {
			display: inline-flex;
			flex-shrink: 0;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-text);
			background: var(--color-surface);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			span {
				display: inline-flex;
				width: 16px;
				height: 16px;
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
