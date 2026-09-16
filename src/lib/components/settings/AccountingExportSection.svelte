<script lang="ts">
	// Financial reconciliation, Part 3: the accountant package download. Pick a period, get one zip of every
	// money ledger for it. Nothing is written; the API streams the file straight down as an attachment, so the
	// browser downloads it without leaving the page -- the same move as the client-book export.
	import {
		CalendarDate,
		endOfMonth,
		startOfMonth,
		today,
		getLocalTimeZone
	} from '@internationalized/date';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	// One download covers at most a year (the API enforces the same rule on the exclusive end date).
	const MAX_DAYS = 366;

	// Last month is what an accountant asks for most; it is complete, so the numbers will not move.
	const lastMonth = startOfMonth(today(getLocalTimeZone()).subtract({ months: 1 }));
	let from = $state<CalendarDate | undefined>(lastMonth);
	let until = $state<CalendarDate | undefined>(endOfMonth(lastMonth));

	// The picker shows an inclusive end date; the readers take an exclusive one, so the request sends the day
	// after what the person chose.
	const exclusiveTo = $derived(until?.add({ days: 1 }));
	const problem = $derived.by(() => {
		if (!from || !until) return 'Choose a start and end date.';
		if (until.compare(from) < 0) return 'The end date must be on or after the start date.';
		if (exclusiveTo!.compare(from) > MAX_DAYS)
			return 'One download covers up to one year. Split a longer period.';
		return null;
	});
	const downloadUrl = $derived(
		problem || !from || !exclusiveTo
			? null
			: `/api/exports/financial?from=${from.toString()}&to=${exclusiveTo.toString()}`
	);
</script>

<SectionBlock
	title="Accounting export"
	hint="One zip with a spreadsheet for each money record — sales, tax, payments, refunds, deposits, balances, job costs, hours, expenses, unbilled work and won deals — plus a totals summary your accountant can check."
	level={2}
	form
>
	<div class="accounting-export">
		<div class="accounting-export__dates">
			<CalendarPicker
				id="accounting-export-from"
				label="From"
				value={from}
				onchange={(value) => (from = value)}
			/>
			<CalendarPicker
				id="accounting-export-until"
				label="To (included)"
				value={until}
				minValue={from}
				onchange={(value) => (until = value)}
			/>
		</div>
		<div class="accounting-export__action">
			<Button
				variant="secondary"
				disabled={downloadUrl === null}
				onclick={() => {
					if (downloadUrl) window.location.href = downloadUrl;
				}}
			>
				<span class="accounting-export__icon" aria-hidden="true">{@html downloadIcon}</span>
				Download package
			</Button>
			{#if problem}
				<p class="accounting-export__problem" role="status">{problem}</p>
			{:else}
				<p class="accounting-export__note">
					Files you are not allowed to see are left out and named in the package's manifest.
				</p>
			{/if}
		</div>
	</div>
</SectionBlock>

<style lang="scss">
	.accounting-export {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__dates {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
			gap: var(--space-base);
			max-width: 520px;
		}

		&__action {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
		}

		&__icon {
			display: inline-flex;
			width: 18px;
			height: 18px;
			margin-right: var(--space-small);

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}

		&__problem,
		&__note {
			margin: 0;
			font-size: var(--typography--fontSize-small);
			color: var(--color-text--secondary);
		}

		&__problem {
			color: var(--color-critical);
		}
	}
</style>
