<script lang="ts">
	import { stripeConnectionQuery } from '$lib/jafar/organization-communications-queries';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { jafarOrganizationStripeConnectionKey } from '$lib/jafar/query-keys';

	type CheckStatus =
		'ok' | 'key_rejected' | 'permission_missing' | 'account_unavailable' | 'webhook_missing';
	type ConnectionStatus =
		| { connected: false }
		| {
				connected: true;
				account_name: string | null;
				stripe_account_id: string;
				livemode: boolean;
				key_last4: string;
				connected_at: string;
				last_checked_at: string;
				last_check_status: CheckStatus;
		  };
	type StatusResponse = { status?: ConnectionStatus; error?: string };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const statusKey = $derived(jafarOrganizationStripeConnectionKey(organizationId));
	const endpoint = $derived(
		`/api/jafar/organizations/${organizationId}/payments/stripe-connection`
	);

	const statusQuery = createQuery<StatusResponse>(() =>
		stripeConnectionQuery<StatusResponse>(organizationId)
	);

	const recheckMutation = createMutation<StatusResponse, Error, void>(() => ({
		mutationFn: async () => {
			const response = await fetch(endpoint, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({})
			});
			const result = (await response.json()) as StatusResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The Stripe connection could not be rechecked.');
			return result;
		},
		onSuccess: async () => {
			await queryClient.invalidateQueries({ queryKey: statusKey });
		}
	}));

	const checkLabels: Record<
		CheckStatus,
		{ label: string; tone: 'success' | 'warning' | 'critical' }
	> = {
		ok: { label: 'Healthy', tone: 'success' },
		key_rejected: { label: 'Key rejected by Stripe', tone: 'critical' },
		permission_missing: { label: 'Key is missing a required permission', tone: 'critical' },
		account_unavailable: { label: 'Stripe could not be reached', tone: 'warning' },
		webhook_missing: { label: 'Webhook endpoint missing or disabled', tone: 'critical' }
	};

	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<div class="stripe-connection-actions">
	<div class="stripe-connection-actions__heading">
		<div>
			<h3>Stripe connection health</h3>
			<p>
				Read-only. The contractor's own restricted key stays with them — Jafar can see whether it is
				working, not reconnect or disconnect it.
			</p>
		</div>
		{#if !statusQuery.isPending && !statusQuery.isError}
			{@const status = statusQuery.data?.status}
			<Badge status={!status?.connected ? 'inactive' : checkLabels[status.last_check_status].tone}>
				{!status?.connected ? 'Not connected' : checkLabels[status.last_check_status].label}
			</Badge>
		{/if}
	</div>

	{#if statusQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading Stripe connection health" />
	{:else if statusQuery.isError}
		<ErrorState
			title="Stripe connection status could not be loaded"
			description={statusQuery.error instanceof Error ? statusQuery.error.message : 'Try again.'}
			retry={() => statusQuery.refetch()}
		/>
	{:else}
		{@const status = statusQuery.data?.status}
		{#if !status?.connected}
			<p class="stripe-connection-actions__empty">
				This organization has not connected a Stripe account yet.
			</p>
		{:else}
			<dl>
				<div>
					<dt>Stripe account</dt>
					<dd>{status.account_name ?? 'Not named'} ({status.stripe_account_id})</dd>
				</div>
				<div>
					<dt>Mode</dt>
					<dd>{status.livemode ? 'Live' : 'Test'}</dd>
				</div>
				<div>
					<dt>Stored key</dt>
					<dd>Ends in {status.key_last4}</dd>
				</div>
				<div>
					<dt>Connected</dt>
					<dd>{formatDateTime(status.connected_at)}</dd>
				</div>
				<div>
					<dt>Last checked</dt>
					<dd>{formatDateTime(status.last_checked_at)}</dd>
				</div>
			</dl>
			<div class="stripe-connection-actions__actions">
				<Button
					size="small"
					variant="secondary"
					variation="subtle"
					loading={recheckMutation.isPending}
					onclick={() => recheckMutation.mutate()}
				>
					Recheck now
				</Button>
			</div>
			{#if recheckMutation.isError}
				<p class="stripe-connection-actions__error" role="alert">
					{recheckMutation.error.message}
				</p>
			{/if}
		{/if}
	{/if}
</div>

<style lang="scss">
	.stripe-connection-actions {
		display: grid;
		gap: var(--space-base);
	}
	.stripe-connection-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.stripe-connection-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.stripe-connection-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.stripe-connection-actions__empty {
		color: var(--color-text--secondary);
	}
	.stripe-connection-actions dl {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.stripe-connection-actions dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.stripe-connection-actions dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.stripe-connection-actions dd {
		margin: 0;
		overflow-wrap: anywhere;
	}
	.stripe-connection-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.stripe-connection-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 639px) {
		.stripe-connection-actions__heading {
			flex-direction: column;
		}
		.stripe-connection-actions dl {
			grid-template-columns: 1fr;
		}
	}
</style>
