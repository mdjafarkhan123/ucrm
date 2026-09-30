<script lang="ts">
	import { marketingAllowanceQuery } from '$lib/jafar/organization-communications-queries';
	import { createQuery } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';

	// Package builder P8b: this shows the Marketing allowance; exceptions to it are added and ended on the
	// Access tab with every other limit.
	type LimitState = 'unlimited' | 'not_included' | 'numeric';
	type Allowance = {
		effective: { state: LimitState; value: number | null; source: 'package' | 'override' };
		override: {
			limit_state: LimitState;
			limit_value: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string | null;
			actor_owner_email: string | null;
		} | null;
	};
	type AllowanceResponse = { allowance?: Allowance; error?: string };

	let { organizationId }: { organizationId: string } = $props();

	const allowanceQuery = createQuery<AllowanceResponse>(() =>
		marketingAllowanceQuery<AllowanceResponse>(organizationId)
	);

	function formatValue(state: LimitState, value: number | null) {
		if (state === 'unlimited') return 'Unlimited marketing emails per month';
		if (state === 'numeric') return `${value ?? 0} marketing emails per month`;
		return 'Not set, Marketing cannot send';
	}

	function formatTime(value: string | null) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not set';
	}
</script>

<div class="marketing-allowance-actions">
	<div>
		<h3>Marketing email allowance</h3>
		<p class="marketing-allowance-actions__hint">
			Monthly marketing emails, kept apart from quote and invoice email. Until this is set,
			Marketing cannot send for this organization.
		</p>
	</div>

	{#if allowanceQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading Marketing allowance" />
	{:else if allowanceQuery.isError}
		<ErrorState
			title="Marketing allowance could not be loaded"
			description={allowanceQuery.error instanceof Error
				? allowanceQuery.error.message
				: 'Marketing allowance could not be loaded. Try again.'}
			retry={() => allowanceQuery.refetch()}
		/>
	{:else if allowanceQuery.data?.allowance}
		{@const allowance = allowanceQuery.data.allowance}
		<div class="marketing-allowance-actions__summary">
			<p>{formatValue(allowance.effective.state, allowance.effective.value)}</p>
			<Badge status={allowance.effective.source === 'override' ? 'informative' : 'inactive'}>
				{allowance.effective.source === 'override' ? 'Exception' : 'Package default'}
			</Badge>
		</div>
		{#if allowance.override}
			<dl class="marketing-allowance-actions__details">
				<div>
					<dt>Stored exception</dt>
					<dd>
						{formatValue(allowance.override.limit_state, allowance.override.limit_value)} from {formatTime(
							allowance.override.starts_at
						)}{allowance.override.expires_at
							? ` until ${formatTime(allowance.override.expires_at)}`
							: ''}
					</dd>
				</div>
				<div>
					<dt>Author and reason</dt>
					<dd>
						{allowance.override.actor_owner_email ?? 'Not recorded'} · {allowance.override.reason ??
							'Not recorded'}
					</dd>
				</div>
			</dl>
		{/if}
		<div class="marketing-allowance-actions__actions">
			<Button size="small" variant="secondary" href="?tab=access">Change on the Access tab</Button>
		</div>
	{/if}
</div>

<style lang="scss">
	.marketing-allowance-actions {
		display: grid;
		gap: var(--space-base);
	}
	.marketing-allowance-actions h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.marketing-allowance-actions__hint {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.marketing-allowance-actions__summary {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text);
	}
	.marketing-allowance-actions__details {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
		div {
			display: grid;
			gap: var(--space-smallest);
		}
		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		dd {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}
	}
	.marketing-allowance-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.marketing-allowance-actions__details {
			grid-template-columns: 1fr;
		}
	}
</style>
