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
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';

	type SenderType = 'long_code' | 'toll_free' | 'short_code' | 'alphanumeric';
	type RetailRate = {
		id: string;
		destination: string;
		sender_type: SenderType;
		message_unit: string;
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
	const listKey = ['jafar', 'communications', 'sms', 'retail-rates'] as const;

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/sms/retail-rates');
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS retail rates could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const senderTypeOptions = [
		{ value: 'long_code', label: 'Long code' },
		{ value: 'toll_free', label: 'Toll-free' },
		{ value: 'short_code', label: 'Short code' },
		{ value: 'alphanumeric', label: 'Alphanumeric' }
	];
	const senderTypeLabel: Record<SenderType, string> = {
		long_code: 'Long code',
		toll_free: 'Toll-free',
		short_code: 'Short code',
		alphanumeric: 'Alphanumeric'
	};

	// Stage 6D-3: a picture text (MMS) bills Twilio as one flat unit per message, not per segment, so it gets
	// its own message-unit rate alongside plain-text 'segment'.
	const messageUnitOptions = [
		{ value: 'segment', label: 'Text (per segment)' },
		{ value: 'mms', label: 'Picture message (per MMS)' }
	];
	const messageUnitLabel: Record<string, string> = {
		segment: 'per segment',
		mms: 'per picture message'
	};

	// Group the flat, newest-first list into one row per destination/sender/message-unit/currency key, each
	// carrying its own version history. The first version in a group whose effective_from has arrived is the
	// one currently charged; anything before it in time is superseded, anything after is scheduled.
	const groups = $derived.by(() => {
		const rates = listQuery.data?.rates ?? [];
		const byKey = new Map<string, RetailRate[]>();
		for (const rate of rates) {
			const key = `${rate.destination}|${rate.sender_type}|${rate.message_unit}|${rate.currency_code}`;
			const versions = byKey.get(key) ?? [];
			versions.push(rate);
			byKey.set(key, versions);
		}
		return [...byKey.entries()]
			.map(([key, versions]) => {
				const now = Date.now();
				const current = versions.find((v) => new Date(v.effective_from).getTime() <= now) ?? null;
				return { key, versions, current };
			})
			.sort((a, b) => a.key.localeCompare(b.key));
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
	let destination = $state('');
	let senderType = $state('long_code');
	let messageUnit = $state('segment');
	let currencyCode = $state('USD');
	let retailRateMajor = $state('');
	let providerCostMajor = $state('');
	let effectiveFrom = $state('');
	let note = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');

	function openPublish() {
		destination = '';
		senderType = 'long_code';
		messageUnit = 'segment';
		currencyCode = 'USD';
		retailRateMajor = '';
		providerCostMajor = '';
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
				const response = await fetch('/api/jafar/communications/sms/retail-rates', {
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
		if (!/^[A-Za-z]{2}$/.test(destination.trim())) {
			fieldErrors = { destination: 'Enter a 2-letter country code.' };
			return;
		}
		const rate = Number(retailRateMajor);
		if (!Number.isFinite(rate) || rate <= 0) {
			fieldErrors = { retail_rate_major: 'Enter a rate greater than zero.' };
			return;
		}
		const body: Record<string, unknown> = {
			destination: destination.trim().toUpperCase(),
			sender_type: senderType,
			message_unit: messageUnit,
			currency_code: currencyCode.trim().toUpperCase(),
			retail_rate_major: rate
		};
		if (providerCostMajor.trim()) {
			const cost = Number(providerCostMajor);
			if (!Number.isFinite(cost) || cost < 0) {
				fieldErrors = { provider_cost_major: 'Provider cost cannot be negative.' };
				return;
			}
			body.provider_cost_major = cost;
		}
		if (effectiveFrom) body.effective_from = localDateTimeToIso(effectiveFrom);
		if (note.trim()) body.note = note.trim();
		publishMutation.mutate(body);
	}
</script>

<Card class="sms-retail-rate-actions__card">
	<div class="sms-retail-rate-actions__heading">
		<div>
			<h2>SMS retail rates</h2>
			<p>
				The price charged per text segment or picture message, by destination and sender type. A new
				rate always takes effect now or on a future date &mdash; past charges keep the rate they
				were sent under. Published rate versions cannot be edited or removed.
			</p>
		</div>
		<Button size="small" variant="secondary" onclick={openPublish}>Publish a rate</Button>
	</div>

	{#if feedbackMessage}<p class="sms-retail-rate-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-retail-rate-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading SMS retail rates" />
	{:else if listQuery.isError}
		<ErrorState
			title="SMS retail rates could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else if groups.length === 0}
		<EmptyState
			title="No rate published yet"
			description="Contractors cannot be charged for SMS in a destination until a rate is published."
		/>
	{:else}
		<ul class="sms-retail-rate-actions__list">
			{#each groups as group (group.key)}
				<li class="sms-retail-rate-actions__row">
					<div class="sms-retail-rate-actions__row-heading">
						<div>
							<h3>
								{group.versions[0].destination} &middot; {senderTypeLabel[
									group.versions[0].sender_type
								]} &middot; {messageUnitLabel[group.versions[0].message_unit] ??
									group.versions[0].message_unit}
							</h3>
							<p>
								{group.current
									? `${formatMoney(group.current.retail_rate_major, group.current.currency_code)} ${messageUnitLabel[group.current.message_unit] ?? group.current.message_unit}`
									: 'No version has taken effect yet'}
							</p>
						</div>
					</div>
					{#if group.versions.length > 1}
						<ul class="sms-retail-rate-actions__history">
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
						<p class="sms-retail-rate-actions__meta">{group.versions[0].note}</p>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</Card>

<Dialog open={publishOpen} title="Publish a retail rate" onClose={() => (publishOpen = false)}>
	<form class="sms-retail-rate-actions__form" onsubmit={submitPublish}>
		<div class="sms-retail-rate-actions__fields">
			<Input
				id="sms-rate-destination"
				label="Destination (2-letter country code)"
				bind:value={destination}
				maxlength={2}
				invalid={Boolean(fieldErrors.destination)}
				errorMessage={fieldErrors.destination}
				required
			/>
			<Select
				id="sms-rate-sender-type"
				label="Sender type"
				options={senderTypeOptions}
				bind:value={senderType}
			/>
			<Select
				id="sms-rate-message-unit"
				label="Message unit"
				options={messageUnitOptions}
				bind:value={messageUnit}
			/>
		</div>
		<div class="sms-retail-rate-actions__fields">
			<Input
				id="sms-rate-retail"
				label={messageUnit === 'mms'
					? 'Retail rate per picture message'
					: 'Retail rate per segment'}
				type="number"
				min="0"
				step="0.0001"
				bind:value={retailRateMajor}
				invalid={Boolean(fieldErrors.retail_rate_major)}
				errorMessage={fieldErrors.retail_rate_major}
				required
			/>
			<Input id="sms-rate-currency" label="Currency code" bind:value={currencyCode} maxlength={3} />
		</div>
		<Input
			id="sms-rate-cost"
			label={messageUnit === 'mms'
				? 'Provider cost per picture message (optional, Jafar-only)'
				: 'Provider cost per segment (optional, Jafar-only)'}
			type="number"
			min="0"
			step="0.0001"
			bind:value={providerCostMajor}
			invalid={Boolean(fieldErrors.provider_cost_major)}
			errorMessage={fieldErrors.provider_cost_major}
		/>
		<DateTimePicker
			id="sms-rate-effective-from"
			dateLabel="Effective from (optional)"
			timeLabel="Effective at"
			value={dateTimePickerValueFromLocalString(effectiveFrom)}
			onchange={handleEffectiveFromChange}
		/>
		<p class="sms-retail-rate-actions__hint">Leave blank to take effect immediately.</p>
		<Textarea
			id="sms-rate-note"
			label="Note (optional)"
			bind:value={note}
			rows={2}
			maxlength={2000}
		/>
		<div class="sms-retail-rate-actions__dialog-actions">
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
	:global(.sms-retail-rate-actions__card) {
		display: grid;
		gap: var(--space-base);
	}
	.sms-retail-rate-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-retail-rate-actions__fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.sms-retail-rate-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-retail-rate-actions__heading h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	.sms-retail-rate-actions__heading p {
		margin: var(--space-small) 0 0;
		max-width: 70ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-retail-rate-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-retail-rate-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-retail-rate-actions__hint {
		margin: calc(var(--space-small) * -1) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-retail-rate-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-retail-rate-actions__row {
		display: grid;
		gap: var(--space-smallest);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-retail-rate-actions__row-heading h3 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-retail-rate-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-retail-rate-actions__meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-retail-rate-actions__history {
		margin: 0;
		padding-left: var(--space-large);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		li {
			margin-top: var(--space-smallest);
		}
	}
	.sms-retail-rate-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-retail-rate-actions__heading,
		.sms-retail-rate-actions__fields {
			flex-direction: column;
			grid-template-columns: 1fr;
		}
	}
</style>
