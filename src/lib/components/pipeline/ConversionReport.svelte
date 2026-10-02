<script lang="ts">
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import { formatMoney } from '$lib/pipeline/money';
	import {
		formatDays,
		formatRate,
		quoteWinRate,
		requestToQuoteRate,
		requestToWonRate,
		workWinRate,
		type StageTime
	} from '$lib/pipeline/conversion';
	import type { ConversionReport, ConversionSource } from '$lib/pipeline/api';
	import fileDescriptionIcon from '@tabler/icons/outline/file-description.svg?raw';
	import trophyIcon from '@tabler/icons/outline/trophy.svg?raw';
	import percentageIcon from '@tabler/icons/outline/percentage.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import routeIcon from '@tabler/icons/outline/route.svg?raw';

	// What became of the work that came in during the chosen period. Three rates that are never blended,
	// each over work that is no longer open; open work is its own figure beside them.
	let { report }: { report: ConversionReport } = $props();

	const requests = $derived(report.requests);
	const quotes = $derived(report.quotes);
	const toQuote = $derived(requestToQuoteRate(requests));
	const toWon = $derived(requestToWonRate(requests));
	const quoteWin = $derived(quoteWinRate(quotes));
	const nothingCreated = $derived(
		requests.total === 0 && quotes.total === 0 && report.stages.length === 0
	);

	function plural(count: number, one: string, many = `${one}s`) {
		return `${count} ${count === 1 ? one : many}`;
	}

	const openNote = $derived.by(() => {
		if (requests.open === 0 && quotes.open === 0) return 'Everything from this period has closed';
		return 'Not counted in the rates until they close';
	});

	const sourceColumns = $derived.by((): DataTableColumn[] => {
		const columns: DataTableColumn[] = [
			{ key: 'source', label: 'Lead source' },
			{ key: 'total', label: 'Came in', align: 'end' },
			{ key: 'won', label: 'Won', align: 'end' },
			{ key: 'not_won', label: 'Not won', align: 'end' },
			{ key: 'open', label: 'Still open', align: 'end' },
			{ key: 'rate', label: 'Win rate', align: 'end' }
		];
		if (report.can_view_value) columns.push({ key: 'value', label: 'Won value', align: 'end' });
		return columns;
	});

	const stageColumns: DataTableColumn[] = [
		{ key: 'stage', label: 'Stage' },
		{ key: 'cards', label: 'Cards', align: 'end' },
		{ key: 'median', label: 'Typical time', align: 'end' },
		{ key: 'average', label: 'Average', align: 'end' },
		{ key: 'now', label: 'There now', align: 'end' }
	];

	function wonValue(source: ConversionSource) {
		if (source.won === 0) return '—';
		if (source.won_value === null || source.won_value === undefined) return 'Unvalued';
		return formatMoney(source.won_value, report) ?? '—';
	}
</script>

{#if nothingCreated}
	<EmptyState
		icon={routeIcon}
		title="No work came in during this period"
		description="Requests and Quotes created in the chosen dates are followed here, from first contact to won."
	/>
{:else}
	<div class="conversion">
		<div class="conversion__tiles">
			<KpiCard
				variant="compact"
				tone="informative"
				label="Requests that got a quote"
				value={formatRate(toQuote)}
				note={toQuote.percent === null
					? requests.total === 0
						? 'No requests in this period'
						: 'All still open, none quoted yet'
					: `${toQuote.hits} of ${plural(toQuote.outOf, 'request')}`}
				icon={fileDescriptionIcon}
			/>
			<KpiCard
				variant="compact"
				tone="success"
				label="Requests won"
				value={formatRate(toWon)}
				note={toWon.percent === null
					? requests.total === 0
						? 'No requests in this period'
						: 'None have closed yet'
					: `${toWon.hits} of ${plural(toWon.outOf, 'closed request')}`}
				icon={trophyIcon}
			/>
			<KpiCard
				variant="compact"
				tone="success"
				label="Quote win rate"
				value={formatRate(quoteWin)}
				note={quoteWin.percent === null
					? 'No quote has been decided yet'
					: `${quoteWin.hits} of ${plural(quoteWin.outOf, 'decided quote')}`}
				icon={percentageIcon}
			/>
			<KpiCard
				variant="compact"
				label="Still open"
				value={String(requests.open + quotes.open)}
				note={requests.open + quotes.open === 0
					? openNote
					: `${plural(requests.open, 'request')} · ${plural(quotes.open, 'quote')} · ${openNote.toLowerCase()}`}
				icon={hourglassIcon}
			/>
		</div>

		{#if quotes.abandoned > 0}
			<p class="conversion__footnote">
				{plural(quotes.abandoned, 'draft quote')}
				{quotes.abandoned === 1 ? 'was' : 'were'} archived before being sent. No customer saw
				{quotes.abandoned === 1 ? 'it' : 'them'}, so {quotes.abandoned === 1 ? 'it is' : 'they are'}
				not counted as won or lost.
			</p>
		{/if}

		<SectionBlock
			title="By lead source"
			hint="Each request, and each quote made without a request, counted once under where the client came from."
		>
			{#if !report.can_view_sources}
				<p class="conversion__note">
					Lead sources are shown to team members who can see every client.
				</p>
			{:else if report.sources.length === 0}
				<p class="conversion__note">No work came in during this period.</p>
			{:else}
				<DataTable
					columns={sourceColumns}
					items={report.sources}
					rowId={(source) => source.lead_source ?? ''}
					caption="Win rate by lead source"
				>
					{#snippet row(source: ConversionSource)}
						{@const sourceRate = workWinRate(source)}
						<th scope="row" class:conversion__muted={!source.lead_source}>
							{source.lead_source ?? 'No source recorded'}
						</th>
						<td class="align-end">{source.total}</td>
						<td class="align-end">{source.won}</td>
						<td class="align-end">{source.lost + source.closed}</td>
						<td class="align-end">{source.open}</td>
						<td class="align-end conversion__strong">{formatRate(sourceRate)}</td>
						{#if report.can_view_value}
							<td class="align-end">{wonValue(source)}</td>
						{/if}
					{/snippet}
				</DataTable>
			{/if}
		</SectionBlock>

		<SectionBlock
			title="Time in each stage"
			hint="How long a card usually sits in a column before it moves on. Typical is the middle card, so one slow job does not skew it."
		>
			{#if report.stages.length === 0}
				<p class="conversion__note">No card from this period has been on the board.</p>
			{:else}
				<DataTable
					columns={stageColumns}
					items={report.stages}
					rowId={(stage) => stage.key}
					caption="Time in each stage"
				>
					{#snippet row(stage: StageTime)}
						<th scope="row">
							<span class="conversion__stage">
								{stage.label}
								<span class="conversion__group">{stage.group}</span>
								{#if stage.retired}
									<Badge status="inactive" size="small">Switched off</Badge>
								{/if}
							</span>
						</th>
						<td class="align-end">{stage.cards}</td>
						<td class="align-end conversion__strong">{formatDays(stage.median_days)}</td>
						<td class="align-end">{formatDays(stage.average_days)}</td>
						<td class="align-end">{stage.still_there}</td>
					{/snippet}
				</DataTable>
			{/if}
		</SectionBlock>
	</div>
{/if}

<style lang="scss">
	.conversion {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	.conversion__tiles {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-small);

		@media (max-width: 1023px) {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		@media (max-width: 479px) {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	.conversion__footnote,
	.conversion__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-large);
	}
	.conversion__stage {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	.conversion__group {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.conversion :global(.conversion__strong) {
		color: var(--color-heading);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.conversion :global(.conversion__muted) {
		color: var(--color-text--secondary);
		font-weight: 400;
	}
</style>
