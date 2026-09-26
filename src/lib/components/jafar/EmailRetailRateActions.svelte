<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';

	type RetailRate = {
		id: string;
		currency_code: string;
		retail_rate_major: number;
		provider_cost_major: number | null;
		effective_from: string;
		note: string | null;
		created_at: string;
	};
	type ListResponse = { rates?: RetailRate[]; error?: string };
	type MutationResponse = {
		rate?: RetailRate;
		error?: string;
		field_errors?: Record<string, string>;
	};

	class RateError extends Error {
		fieldErrors: Record<string, string>;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The rate could not be published.');
			this.fieldErrors = result.field_errors ?? {};
		}
	}

	const queryClient = useQueryClient();
	const listKey = ['jafar', 'communications', 'email', 'retail-rates'] as const;

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/email/retail-rates');
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Email retail rates could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	// Group the flat, newest-first list into one row per currency, each carrying its own version history. The
	// first version whose effective_from has arrived is the one currently charged; anything before it in time
	// is superseded, anything after is scheduled. Mirrors SmsRetailRateActions' grouping, minus the SMS-only
	// destination/sender/message-unit dimensions -- email has one price per currency.
	const groups = $derived.by(() => {
		const rates = listQuery.data?.rates ?? [];
		const byKey = new Map<string, RetailRate[]>();
		for (const rate of rates) {
			const versions = byKey.get(rate.currency_code) ?? [];
			versions.push(rate);
			byKey.set(rate.currency_code, versions);
		}
		return [...byKey.entries()]
			.map(([currencyCode, versions]) => {
				const now = Date.now();
				const current = versions.find((v) => new Date(v.effective_from).getTime() <= now) ?? null;
				return { currencyCode, versions, current };
			})
			.sort((a, b) => a.currencyCode.localeCompare(b.currencyCode));
	});

	function formatMoney(major: number, currency: string) {
		return `${major.toFixed(4)} ${currency}`;
	}
	function formatTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	let publishOpen = $state(false);
	let currencyCode = $state('USD');
	// Input's type="number" binds back a JS number, or null when empty -- never a string to .trim().
	let retailRateMajor = $state<number | null>(null);
	let providerCostMajor = $state<number | null>(null);
	let effectiveFrom = $state('');
	let note = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');

	function openPublish() {
		currencyCode = 'USD';
		retailRateMajor = null;
		providerCostMajor = null;
		effectiveFrom = '';
		note = '';
		fieldErrors = {};
		feedbackError = '';
		publishOpen = true;
	}
	function handleEffectiveFromChange(value: DateTimePickerValue) {
		effectiveFrom = dateTimePickerValueToLocalString(value);
	}

	const publishMutation = createMutation<MutationResponse, RateError, Record<string, unknown>>(
		() => ({
			mutationFn: async (body) => {
				const response = await fetch('/api/jafar/communications/email/retail-rates', {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				});
				const result = (await response.json()) as MutationResponse;
				if (!response.ok) throw new RateError(result);
				return result;
			},
			onMutate: () => {
				fieldErrors = {};
				feedbackError = '';
			},
			onError: (error) => {
				fieldErrors = error.fieldErrors;
				feedbackError = error.message;
			},
			onSuccess: async () => {
				publishOpen = false;
				feedbackMessage = 'Rate published.';
				await queryClient.invalidateQueries({ queryKey: listKey });
			}
		})
	);

	function submitPublish(event: SubmitEvent) {
		event.preventDefault();
		if (retailRateMajor === null || !Number.isFinite(retailRateMajor) || retailRateMajor <= 0) {
			fieldErrors = { retail_rate_major: 'Enter a rate greater than zero.' };
			return;
		}
		const body: Record<string, unknown> = {
			currency_code: currencyCode.trim().toUpperCase(),
			retail_rate_major: retailRateMajor
		};
		if (providerCostMajor !== null) {
			if (!Number.isFinite(providerCostMajor) || providerCostMajor < 0) {
				fieldErrors = { provider_cost_major: 'Provider cost cannot be negative.' };
				return;
			}
			body.provider_cost_major = providerCostMajor;
		}
		if (effectiveFrom) body.effective_from = localDateTimeToIso(effectiveFrom);
		if (note.trim()) body.note = note.trim();
		publishMutation.mutate(body);
	}
</script>

<Card class="email-retail-rate-actions__card">
	<div class="email-retail-rate-actions__heading">
		<div>
			<h2>Over-allowance email retail rate</h2>
			<p>
				The price charged per 1,000 recipients once an organization's optional email goes past its
				package allowance and self-funds from its Communication Balance. Essential email (receipts,
				invoices, quotes) is never limited or charged this way. A new rate always takes effect now
				or on a future date &mdash; past charges keep the rate they were sent under. Published rate
				versions cannot be edited or removed.
			</p>
			<p class="email-retail-rate-actions__reference">
				For reference: Amazon SES actually costs UCRM about $0.10 per 1,000 emails. In the industry,
				HighLevel charges about $0.675 per 1,000 from a prepaid wallet, Mailchimp bills overage in
				blocks on the next invoice, and Jobber has no limit at all.
			</p>
		</div>
		<Button size="small" variant="secondary" onclick={openPublish}>Publish a rate</Button>
	</div>

	{#if feedbackMessage}<p class="email-retail-rate-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="email-retail-rate-actions__error" role="alert">
			{feedbackError}
		</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading email retail rates" />
	{:else if listQuery.isError}
		<ErrorState
			title="Email retail rates could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else if groups.length === 0}
		<EmptyState
			title="No rate published yet"
			description="No organization can be charged for over-allowance email until a rate is published."
		/>
	{:else}
		<ul class="email-retail-rate-actions__list">
			{#each groups as group (group.currencyCode)}
				<li class="email-retail-rate-actions__row">
					<div class="email-retail-rate-actions__row-heading">
						<div>
							<h3>{group.currencyCode} &middot; per 1,000 recipients</h3>
							<p>
								{group.current
									? `${formatMoney(group.current.retail_rate_major, group.current.currency_code)} per 1,000`
									: 'No version has taken effect yet'}
							</p>
						</div>
					</div>
					{#if group.versions.length > 1}
						<ul class="email-retail-rate-actions__history">
							{#each group.versions as version (version.id)}
								<li>
									{formatMoney(version.retail_rate_major, version.currency_code)} &middot; effective
									{formatTime(version.effective_from)}
									{version.id === group.current?.id ? ' (current)' : ''}
									{#if version.note}&middot; {version.note}{/if}
								</li>
							{/each}
						</ul>
					{:else if group.versions[0].note}
						<p class="email-retail-rate-actions__meta">{group.versions[0].note}</p>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</Card>

<Dialog open={publishOpen} title="Publish a retail rate" onClose={() => (publishOpen = false)}>
	<form class="email-retail-rate-actions__form" onsubmit={submitPublish}>
		<div class="email-retail-rate-actions__fields">
			<Input
				id="email-rate-retail"
				label="Retail rate per 1,000 recipients"
				type="number"
				min="0"
				step="0.0001"
				bind:value={retailRateMajor}
				invalid={Boolean(fieldErrors.retail_rate_major)}
				errorMessage={fieldErrors.retail_rate_major}
				required
			/>
			<Input
				id="email-rate-currency"
				label="Currency code"
				bind:value={currencyCode}
				maxlength={3}
			/>
		</div>
		<Input
			id="email-rate-cost"
			label="Provider cost per 1,000 recipients (optional, Jafar-only)"
			type="number"
			min="0"
			step="0.0001"
			bind:value={providerCostMajor}
			invalid={Boolean(fieldErrors.provider_cost_major)}
			errorMessage={fieldErrors.provider_cost_major}
		/>
		<DateTimePicker
			id="email-rate-effective-from"
			dateLabel="Effective from (optional)"
			timeLabel="Effective at"
			value={dateTimePickerValueFromLocalString(effectiveFrom)}
			onchange={handleEffectiveFromChange}
		/>
		<p class="email-retail-rate-actions__hint">Leave blank to take effect immediately.</p>
		<Textarea
			id="email-rate-note"
			label="Note (optional)"
			bind:value={note}
			rows={2}
			maxlength={2000}
		/>
		<div class="email-retail-rate-actions__dialog-actions">
			<Button type="submit" loading={publishMutation.isPending}>Publish rate</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (publishOpen = false)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	:global(.email-retail-rate-actions__card) {
		display: grid;
		gap: var(--space-base);
	}
	.email-retail-rate-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.email-retail-rate-actions__fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.email-retail-rate-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.email-retail-rate-actions__heading h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	.email-retail-rate-actions__heading p {
		margin: var(--space-small) 0 0;
		max-width: 70ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.email-retail-rate-actions__reference {
		font-style: italic;
	}
	.email-retail-rate-actions__success {
		color: var(--color-success--onSurface);
	}
	.email-retail-rate-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.email-retail-rate-actions__hint {
		margin: calc(var(--space-small) * -1) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-retail-rate-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.email-retail-rate-actions__row {
		display: grid;
		gap: var(--space-smallest);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.email-retail-rate-actions__row-heading h3 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.email-retail-rate-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-retail-rate-actions__meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-retail-rate-actions__history {
		margin: 0;
		padding-left: var(--space-large);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		li {
			margin-top: var(--space-smallest);
		}
	}
	.email-retail-rate-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.email-retail-rate-actions__heading,
		.email-retail-rate-actions__fields {
			flex-direction: column;
			grid-template-columns: 1fr;
		}
	}
</style>
