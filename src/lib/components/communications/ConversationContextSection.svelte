<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		conversationContextSectionKey,
		fetchConversationContextSection,
		type ConversationContextInvoice,
		type ConversationContextJob,
		type ConversationContextOpportunity,
		type ConversationContextProperty,
		type ConversationContextQuote,
		type ConversationContextRequest
	} from '$lib/communications/inbox';
	import {
		CONTEXT_SECTION_LABELS,
		type ContextSection
	} from '$lib/communications/context-sections';
	import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONES } from '$lib/quotes/statuses';
	import { REQUEST_STATUS_LABELS, REQUEST_STATUS_TONES } from '$lib/requests/statuses';
	import { JOB_STATUS_LABELS, JOB_STATUS_TONES } from '$lib/jobs/statuses';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import { ALL_STAGE_LABELS } from '$lib/pipeline/stages';
	import { OUTCOME_TYPE_LABELS } from '$lib/pipeline/outcomes';
	import type { StatusTone } from '$lib/components/work/types';

	// One tab of the customer context rail: the customer's latest records of one kind. It mounts only when
	// its tab is open, so its query stays off until then; the rail warms the same key on hover, which is why
	// a click usually finds the list already there.
	let {
		clientId,
		section
	}: {
		clientId: string;
		section: ContextSection;
	} = $props();

	const query = createQuery(() => ({
		queryKey: conversationContextSectionKey(clientId, section),
		queryFn: () => fetchConversationContextSection(clientId, section),
		staleTime: 30_000
	}));

	const locale = $derived(query.data?.locale ?? 'en-US');
	const items = $derived(query.data?.items ?? []);
	const noun = $derived(CONTEXT_SECTION_LABELS[section].toLowerCase());

	// A dash where a money figure is withheld, so nobody mistakes "may not see" for "nothing owed".
	function formatMoney(amountMinor: number | null, currency: string) {
		if (amountMinor === null) return null;
		return new Intl.NumberFormat(locale, { style: 'currency', currency }).format(amountMinor / 100);
	}

	const sameYear = new Date().getFullYear();
	function formatDay(value: string) {
		// A `date` column arrives as `YYYY-MM-DD`; reading it as local midnight keeps the calendar day.
		const date = new Date(value.length === 10 ? `${value}T00:00` : value);
		return new Intl.DateTimeFormat(locale, {
			month: 'short',
			day: 'numeric',
			...(date.getFullYear() === sameYear ? {} : { year: 'numeric' })
		}).format(date);
	}

	function status<Label extends string>(
		key: string,
		labels: Record<Label, string>,
		tones: Record<Label, StatusTone>
	): { label: string; tone: StatusTone } {
		const known = key as Label;
		return { label: labels[known] ?? key, tone: tones[known] ?? 'inactive' };
	}

	// A decided opportunity says how it ended; an open one says where it sits on the board. `request_closed`
	// is the off-board parking stage, so it never has a board name of its own.
	function opportunityBadge(opportunity: ConversationContextOpportunity): {
		label: string;
		tone: StatusTone;
	} {
		if (opportunity.outcome === 'won') return { label: OUTCOME_TYPE_LABELS.won, tone: 'success' };
		if (opportunity.outcome === 'lost')
			return { label: OUTCOME_TYPE_LABELS.lost, tone: 'inactive' };
		const label = ALL_STAGE_LABELS[opportunity.stage as keyof typeof ALL_STAGE_LABELS];
		return label ? { label, tone: 'informative' } : { label: 'Request closed', tone: 'inactive' };
	}

	function invoiceMeta(invoice: ConversationContextInvoice) {
		const parts = [`#${invoice.invoice_number}`, `Due ${formatDay(invoice.due_date)}`];
		const left = formatMoney(invoice.remaining_minor, invoice.currency_code);
		// A part-paid bill is the one case the status pill alone cannot explain.
		if (
			left &&
			invoice.remaining_minor !== null &&
			invoice.total_minor !== null &&
			invoice.remaining_minor > 0 &&
			invoice.remaining_minor < invoice.total_minor
		) {
			parts.push(`${left} left`);
		}
		return parts.join(' · ');
	}
</script>

{#snippet pill(tone: StatusTone, label: string)}
	<Badge size="small" status={tone}>{label}</Badge>
{/snippet}

{#snippet amount(minor: number | null, currency: string)}
	{@const text = formatMoney(minor, currency)}
	{#if text}<span class="context-section__amount">{text}</span>{/if}
{/snippet}

<div class="context-section">
	{#if query.isPending}
		<div class="context-section__loading">
			<LoadingSkeleton variant="card" label={`Loading ${noun}`} />
			<LoadingSkeleton variant="card" label={`Loading ${noun}`} />
		</div>
	{:else if query.isError}
		<div class="context-section__note">
			<p>{CONTEXT_SECTION_LABELS[section]} could not be loaded.</p>
			<Button size="small" variant="secondary" onclick={() => query.refetch()}>Try again</Button>
		</div>
	{:else if items.length === 0}
		<p class="context-section__empty">No {noun} for this customer yet.</p>
	{:else}
		<ul class="context-section__list">
			{#if section === 'properties'}
				{#each items as property (property.id)}
					{@const row = property as ConversationContextProperty}
					<li class="context-section__row">
						<span class="context-section__main">
							<span class="context-section__title">{row.address_line1}</span>
							<span class="context-section__meta">
								{row.city}{row.state_region ? `, ${row.state_region}` : ''}{row.postal_code
									? ` ${row.postal_code}`
									: ''}
							</span>
						</span>
					</li>
				{/each}
			{:else if section === 'requests'}
				{#each items as request (request.id)}
					{@const row = request as ConversationContextRequest}
					{@const badge = status(row.status, REQUEST_STATUS_LABELS, REQUEST_STATUS_TONES)}
					<li class="context-section__row">
						<a
							class="context-section__link"
							href={resolve('/(app)/requests/[id=uuid]', { id: row.id })}
						>
							<span class="context-section__main">
								<span class="context-section__title">{row.title}</span>
								<span class="context-section__meta">{formatDay(row.created_at)}</span>
							</span>
							<span class="context-section__side">{@render pill(badge.tone, badge.label)}</span>
						</a>
					</li>
				{/each}
			{:else if section === 'quotes'}
				{#each items as quote (quote.id)}
					{@const row = quote as ConversationContextQuote}
					{@const badge = status(row.status, QUOTE_STATUS_LABELS, QUOTE_STATUS_TONES)}
					<li class="context-section__row">
						<a
							class="context-section__link"
							href={resolve('/(app)/quotes/[id=uuid]', { id: row.id })}
						>
							<span class="context-section__main">
								<span class="context-section__title">{row.title}</span>
								<span class="context-section__meta"
									>#{row.quote_number} · {formatDay(row.created_at)}</span
								>
							</span>
							<span class="context-section__side">
								{@render amount(row.total_minor, row.currency_code)}
								{@render pill(badge.tone, badge.label)}
							</span>
						</a>
					</li>
				{/each}
			{:else if section === 'jobs'}
				{#each items as job (job.id)}
					{@const row = job as ConversationContextJob}
					{@const badge = status(row.derived_status, JOB_STATUS_LABELS, JOB_STATUS_TONES)}
					<li class="context-section__row">
						<a
							class="context-section__link"
							href={resolve('/(app)/jobs/[id=uuid]', { id: row.id })}
						>
							<span class="context-section__main">
								<span class="context-section__title">{row.title}</span>
								<span class="context-section__meta"
									>#{row.job_number} · {formatDay(row.created_at)}</span
								>
							</span>
							<span class="context-section__side">
								{@render amount(row.total_minor, row.currency_code)}
								{@render pill(badge.tone, badge.label)}
							</span>
						</a>
					</li>
				{/each}
			{:else if section === 'invoices'}
				{#each items as invoice (invoice.id)}
					{@const row = invoice as ConversationContextInvoice}
					{@const badge = status(row.derived_status, INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES)}
					<li class="context-section__row">
						<a
							class="context-section__link"
							href={resolve('/(app)/invoices/[id=uuid]', { id: row.id })}
						>
							<span class="context-section__main">
								<span class="context-section__title">{row.subject}</span>
								<span class="context-section__meta">{invoiceMeta(row)}</span>
							</span>
							<span class="context-section__side">
								{@render amount(row.total_minor, row.currency_code)}
								{@render pill(badge.tone, badge.label)}
							</span>
						</a>
					</li>
				{/each}
			{:else if section === 'pipeline'}
				{#each items as opportunity (opportunity.id)}
					{@const row = opportunity as ConversationContextOpportunity}
					{@const badge = opportunityBadge(row)}
					<li class="context-section__row">
						<span class="context-section__main">
							<span class="context-section__title">{row.title}</span>
							<span class="context-section__meta">{formatDay(row.created_at)}</span>
						</span>
						<span class="context-section__side">{@render pill(badge.tone, badge.label)}</span>
					</li>
				{/each}
			{/if}
		</ul>
		{#if query.data?.has_more}
			<a class="context-section__more" href={resolve('/(app)/clients/[id=uuid]', { id: clientId })}>
				See everything on the client page
			</a>
		{/if}
	{/if}
</div>

<style lang="scss">
	.context-section {
		display: grid;
		gap: var(--space-small);
	}

	.context-section__loading,
	.context-section__list {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.context-section__row {
		display: flex;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition:
			border-color var(--timing-base) ease-out,
			background var(--timing-base) ease-out;

		&:has(.context-section__link:hover),
		&:has(.context-section__link:focus-visible) {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}
	}

	/* The row is the target: one link across the whole card, not a small link buried inside it. */
	.context-section__row > .context-section__main,
	.context-section__row > .context-section__side,
	.context-section__link {
		padding: var(--space-small) var(--space-slim, 12px);
	}

	.context-section__link {
		display: flex;
		flex: 1;
		min-width: 0;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		border-radius: var(--radius-base);
		color: inherit;
		text-decoration: none;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.context-section__row > .context-section__main {
		flex: 1;
	}

	.context-section__main {
		display: grid;
		min-width: 0;
		gap: 2px;
	}

	.context-section__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: 1.3;
		overflow-wrap: anywhere;
	}

	.context-section__meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.context-section__side {
		display: grid;
		flex: 0 0 auto;
		align-content: center;
		justify-items: end;
		gap: var(--space-smaller);
	}

	.context-section__amount {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}

	.context-section__empty,
	.context-section__note p {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.context-section__empty {
		padding: var(--space-large) var(--space-base);
		border: var(--border-base) dashed var(--color-border);
		border-radius: var(--radius-base);
		text-align: center;
	}

	.context-section__note {
		display: grid;
		justify-items: start;
		gap: var(--space-small);
	}

	.context-section__more {
		justify-self: start;
		color: var(--color-interactive--subtle);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}
</style>
