<script lang="ts">
	import { emailAllowancesQuery } from '$lib/jafar/organization-communications-queries';
	import { createQuery } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';

	// Package builder P8b: this shows the email allowances; exceptions to them are added and ended on the
	// Access tab with every other limit.
	type AllowanceKey = 'operational_email_recipients' | 'essential_email_recipients';
	type Allowance = {
		limit_key: AllowanceKey;
		period_id: string | null;
		period_starts_at: string | null;
		period_ends_at: string | null;
		effective_state: 'unlimited' | 'not_included' | 'numeric' | null;
		effective_value: number | null;
		effective_source: 'package' | 'override';
		fallback_state: 'unlimited' | 'not_included' | 'numeric' | null;
		fallback_value: number | null;
		override_state: 'unlimited' | 'not_included' | 'numeric' | null;
		override_value: number | null;
		override_starts_at: string | null;
		override_expires_at: string | null;
		override_reason: string | null;
		override_author_email: string | null;
	};
	type AllowanceResponse = { allowances?: Allowance[]; error?: string };

	let { organizationId }: { organizationId: string } = $props();

	const allowancesQuery = createQuery<AllowanceResponse>(() =>
		emailAllowancesQuery<AllowanceResponse>(organizationId)
	);

	const labels: Record<AllowanceKey, { title: string; description: string; unit: string }> = {
		operational_email_recipients: {
			title: 'Operational email allowance',
			description: 'Optional operational email can use this package capacity.',
			unit: 'recipients'
		},
		essential_email_recipients: {
			title: 'Protected essential reserve',
			description:
				'Requested quotes, invoices, receipts, security notices, and direct replies use this reserve.',
			unit: 'recipients'
		}
	};
	function formatValue(state: Allowance['effective_state'], value: number | null) {
		if (state === 'unlimited') return 'Unlimited recipients';
		if (state === 'numeric') return `${value ?? 0} recipients`;
		if (state === 'not_included') return 'Not included';
		return 'Not configured';
	}

	function formatTime(value: string | null) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not set';
	}
</script>

<div class="email-allowance-actions">
	<div class="email-allowance-actions__heading">
		<div>
			<h3>Email allowance authority</h3>
			<p>These values control package capacity only. The email delivery worker remains disabled.</p>
		</div>
	</div>

	{#if allowancesQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading email allowance authority" />
	{:else if allowancesQuery.isError}
		<ErrorState
			title="Email allowances could not be loaded"
			description={allowancesQuery.error instanceof Error
				? allowancesQuery.error.message
				: 'Email allowances could not be loaded. Try again.'}
			retry={() => allowancesQuery.refetch()}
		/>
	{:else}
		{#each allowancesQuery.data?.allowances ?? [] as allowance (allowance.limit_key)}
			<section
				class="email-allowance-actions__allowance"
				aria-labelledby={`allowance-${allowance.limit_key}`}
			>
				<div class="email-allowance-actions__allowance-heading">
					<div>
						<h4 id={`allowance-${allowance.limit_key}`}>{labels[allowance.limit_key].title}</h4>
						<p>{labels[allowance.limit_key].description}</p>
					</div>
					<Badge status={allowance.effective_source === 'override' ? 'informative' : 'inactive'}>
						{allowance.effective_source === 'override' ? 'Exception' : 'Package default'}
					</Badge>
				</div>
				<dl>
					<div>
						<dt>Effective value</dt>
						<dd>{formatValue(allowance.effective_state, allowance.effective_value)}</dd>
					</div>
					<div>
						<dt>Package fallback</dt>
						<dd>{formatValue(allowance.fallback_state, allowance.fallback_value)}</dd>
					</div>
					<div>
						<dt>Current period</dt>
						<dd>
							{allowance.period_id
								? `${formatTime(allowance.period_starts_at)} to ${formatTime(allowance.period_ends_at)}`
								: 'Not opened — sending stays fail-closed'}
						</dd>
					</div>
					{#if allowance.override_state}
						<div>
							<dt>Stored exception</dt>
							<dd>
								{formatValue(allowance.override_state, allowance.override_value)} from {formatTime(
									allowance.override_starts_at
								)}{allowance.override_expires_at
									? ` until ${formatTime(allowance.override_expires_at)}`
									: ''}
							</dd>
						</div>
						<div>
							<dt>Author and reason</dt>
							<dd>
								{allowance.override_author_email ?? 'Not recorded'} · {allowance.override_reason ??
									'Not recorded'}
							</dd>
						</div>
					{/if}
				</dl>
			</section>
		{/each}
		<div class="email-allowance-actions__actions">
			<Button size="small" variant="secondary" href="?tab=access">Change on the Access tab</Button>
		</div>
	{/if}
</div>

<style lang="scss">
	.email-allowance-actions {
		display: grid;
		gap: var(--space-base);
	}
	.email-allowance-actions__heading h3,
	.email-allowance-actions__allowance h4 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.email-allowance-actions__heading p,
	.email-allowance-actions__allowance-heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.email-allowance-actions__allowance {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.email-allowance-actions__allowance-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.email-allowance-actions__allowance dl {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.email-allowance-actions__allowance dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.email-allowance-actions__allowance dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-allowance-actions__allowance dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	.email-allowance-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.email-allowance-actions__allowance-heading {
			flex-direction: column;
		}
		.email-allowance-actions__allowance dl {
			grid-template-columns: 1fr;
		}
	}
</style>
