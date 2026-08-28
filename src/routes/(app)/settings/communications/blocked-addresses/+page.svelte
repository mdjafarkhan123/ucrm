<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';

	type OpenRequest = {
		id: string;
		request_reason: string;
		requested_by_email: string;
		created_at: string;
	};
	type BlockedAddress = {
		suppression_id: string;
		recipient_email: string;
		reason: 'complaint' | 'hard_bounce';
		source: string;
		created_at: string;
		client_id: string | null;
		client_display_name: string | null;
		open_request: OpenRequest | null;
	};
	type ClearedAddress = {
		suppression_id: string;
		recipient_email: string;
		reason: 'complaint' | 'hard_bounce';
		released_at: string;
		released_by_kind: 'organization_admin' | 'platform_owner' | null;
		released_reason: string | null;
	};
	type BlockedResponse = {
		blocked: BlockedAddress[];
		blocked_total: number;
		recently_cleared: ClearedAddress[];
	};

	const blockedKey = ['settings', 'communications', 'blocked-addresses'] as const;
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const blockedQuery = createQuery<BlockedResponse>(() => ({
		queryKey: blockedKey,
		queryFn: async () => {
			const response = await fetch('/api/settings/communications/blocked-addresses');
			const result = (await response.json()) as BlockedResponse & { error?: string };
			if (!response.ok) throw new Error(result.error ?? 'Blocked addresses could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const blocked = $derived(blockedQuery.data?.blocked ?? []);
	const cleared = $derived(blockedQuery.data?.recently_cleared ?? []);
	const overCap = $derived((blockedQuery.data?.blocked_total ?? 0) > blocked.length);

	let requestTarget = $state<BlockedAddress | null>(null);
	let withdrawTarget = $state<BlockedAddress | null>(null);
	let reason = $state('');
	let evidence = $state('');
	let consent = $state(false);

	const formValid = $derived(reason.trim().length >= 3 && evidence.trim().length >= 1 && consent);

	function applyResponse(next: BlockedResponse) {
		queryClient.setQueryData<BlockedResponse>(blockedKey, {
			blocked: next.blocked,
			blocked_total: next.blocked_total,
			recently_cleared: next.recently_cleared
		});
	}

	function openRequest(address: BlockedAddress) {
		requestTarget = address;
		reason = '';
		evidence = '';
		consent = false;
	}
	function closeRequest() {
		if (requestMutation.isPending) return;
		requestTarget = null;
	}

	const requestMutation = createMutation<
		BlockedResponse & { request: { suppression_reason: string; status: string } },
		Error,
		{ suppressionId: string }
	>(() => ({
		mutationFn: async ({ suppressionId }) => {
			const response = await fetch(
				`/api/settings/communications/blocked-addresses/${suppressionId}/removal-request`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						reason: reason.trim(),
						evidence: evidence.trim(),
						consent_confirmed: consent
					})
				}
			);
			const result = (await response.json()) as BlockedResponse & {
				request: { suppression_reason: string; status: string };
				error?: string;
			};
			if (!response.ok) throw new Error(result.error ?? 'The removal request could not be filed.');
			return result;
		},
		onSuccess: (result) => {
			applyResponse(result);
			const wasBounce = result.request.suppression_reason === 'hard_bounce';
			requestTarget = null;
			toast.success(
				wasBounce
					? 'Address unblocked. Your team can email it again.'
					: "Removal request sent. We'll review it and let you know."
			);
		},
		onError: (error) => toast.error(error.message)
	}));

	const withdrawMutation = createMutation<BlockedResponse, Error, { suppressionId: string }>(
		() => ({
			mutationFn: async ({ suppressionId }) => {
				const response = await fetch(
					`/api/settings/communications/blocked-addresses/${suppressionId}/removal-request`,
					{ method: 'DELETE' }
				);
				const result = (await response.json()) as BlockedResponse & { error?: string };
				if (!response.ok)
					throw new Error(result.error ?? 'The removal request could not be withdrawn.');
				return result;
			},
			onSuccess: (result) => {
				applyResponse(result);
				withdrawTarget = null;
				toast.success('Removal request withdrawn.');
			},
			onError: (error) => toast.error(error.message)
		})
	);

	function reasonLabel(reason: 'complaint' | 'hard_bounce') {
		return reason === 'hard_bounce' ? 'Hard bounce' : 'Spam complaint';
	}
	function reasonTone(reason: 'complaint' | 'hard_bounce') {
		return reason === 'hard_bounce' ? ('warning' as const) : ('critical' as const);
	}
	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
	}
	function clearedBy(kind: ClearedAddress['released_by_kind']) {
		if (kind === 'organization_admin') return 'your team';
		if (kind === 'platform_owner') return 'UpliftContractor';
		return 'UpliftContractor';
	}
</script>

<svelte:head><title>Blocked addresses · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="blocked">
		<PageHeader
			eyebrow="Communications"
			title="Blocked addresses"
			description="When a customer's email keeps bouncing or they mark your email as spam, UCRM stops sending to that address to protect your sender reputation. Corrected addresses can be unblocked here."
		>
			{#snippet actions()}
				<Button href={resolve('/settings')} variant="secondary" variation="subtle">
					Back to settings
				</Button>
			{/snippet}
		</PageHeader>

		<SectionBlock
			title="Blocked email addresses"
			hint="Nothing your team sends reaches these addresses until they are unblocked."
			icon={mailOffIcon}
			level={2}
		>
			{#if blockedQuery.isPending}
				<LoadingSkeleton variant="table" label="Loading blocked addresses" />
			{:else if blockedQuery.isError}
				<ErrorState
					description="Blocked addresses could not be loaded."
					retry={() => blockedQuery.refetch()}
				/>
			{:else if blocked.length === 0}
				<EmptyState
					title="No blocked addresses"
					description="Every customer address your team emails is currently deliverable."
				/>
			{:else}
				{#if overCap}
					<p class="blocked__notice" role="status">
						Showing the {blocked.length} most recent of {blockedQuery.data?.blocked_total} blocked addresses.
					</p>
				{/if}
				<div class="blocked__table-wrap">
					<table class="blocked__table">
						<thead>
							<tr>
								<th scope="col">Address</th>
								<th scope="col">Why</th>
								<th scope="col">Blocked</th>
								<th scope="col">Status</th>
								<th scope="col"><span class="blocked__sr-only">Actions</span></th>
							</tr>
						</thead>
						<tbody>
							{#each blocked as address (address.suppression_id)}
								<tr>
									<th scope="row">
										<strong>{address.recipient_email}</strong>
										{#if address.client_display_name}
											<small>{address.client_display_name}</small>
										{/if}
									</th>
									<td>
										<Badge status={reasonTone(address.reason)} dot={false}>
											{reasonLabel(address.reason)}
										</Badge>
									</td>
									<td>{formatDate(address.created_at)}</td>
									<td>
										{#if address.open_request}
											<Badge status="informative" dot={false}>Removal pending review</Badge>
										{:else}
											<Badge status="inactive" dot={false}>Blocked</Badge>
										{/if}
									</td>
									<td class="blocked__row-action">
										{#if address.open_request}
											<Button
												size="small"
												variant="secondary"
												variation="subtle"
												onclick={() => (withdrawTarget = address)}
											>
												Withdraw request
											</Button>
										{:else}
											<Button
												size="small"
												variant="secondary"
												variation="subtle"
												onclick={() => openRequest(address)}
											>
												Request removal
											</Button>
										{/if}
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</SectionBlock>

		{#if cleared.length > 0}
			<SectionBlock title="Recently unblocked" icon={mailOffIcon} level={2}>
				<div class="blocked__table-wrap">
					<table class="blocked__table">
						<thead>
							<tr>
								<th scope="col">Address</th>
								<th scope="col">Was blocked for</th>
								<th scope="col">Unblocked</th>
								<th scope="col">By</th>
							</tr>
						</thead>
						<tbody>
							{#each cleared as address (address.suppression_id)}
								<tr>
									<th scope="row">{address.recipient_email}</th>
									<td>{reasonLabel(address.reason)}</td>
									<td>{formatDate(address.released_at)}</td>
									<td>{clearedBy(address.released_by_kind)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</SectionBlock>
		{/if}
	</div>
</PageContainer>

{#if requestTarget}
	{@const isBounce = requestTarget.reason === 'hard_bounce'}
	<Dialog open title="Request removal" onClose={closeRequest}>
		<form
			class="blocked__form"
			onsubmit={(event) => {
				event.preventDefault();
				if (formValid && requestTarget)
					requestMutation.mutate({ suppressionId: requestTarget.suppression_id });
			}}
		>
			<p class="blocked__form-lead">
				<strong>{requestTarget.recipient_email}</strong> was blocked after a
				{isBounce ? 'hard bounce' : 'spam complaint'}.
				{#if isBounce}
					Once you confirm the address is corrected, it is unblocked right away.
				{:else}
					Removing a spam-complaint block needs UpliftContractor's approval, so this becomes a
					request we review.
				{/if}
			</p>
			<Textarea
				id="removal-reason"
				label="Why should this address be unblocked?"
				bind:value={reason}
				rows={3}
				maxlength={1000}
				required
			/>
			<Textarea
				id="removal-evidence"
				label="How did you confirm it is safe to email again?"
				bind:value={evidence}
				rows={3}
				maxlength={2000}
				required
			/>
			<Checkbox
				id="removal-consent"
				label="I confirm this customer still wants to receive email from us."
				bind:checked={consent}
			/>
			<div class="blocked__form-actions">
				<Button type="submit" loading={requestMutation.isPending} disabled={!formValid}>
					{isBounce ? 'Unblock address' : 'Send request'}
				</Button>
				<Button
					type="button"
					variant="secondary"
					variation="subtle"
					disabled={requestMutation.isPending}
					onclick={closeRequest}
				>
					Cancel
				</Button>
			</div>
		</form>
	</Dialog>
{/if}

<ConfirmDialog
	open={withdrawTarget !== null}
	title="Withdraw removal request"
	confirmLabel="Withdraw request"
	loading={withdrawMutation.isPending}
	confirmDisabled={withdrawMutation.isPending}
	onConfirm={() => {
		if (withdrawTarget) withdrawMutation.mutate({ suppressionId: withdrawTarget.suppression_id });
	}}
	onClose={() => {
		if (!withdrawMutation.isPending) withdrawTarget = null;
	}}
>
	<p>
		The pending request for <strong>{withdrawTarget?.recipient_email}</strong> is cancelled. The address
		stays blocked, and you can file a new request later.
	</p>
</ConfirmDialog>

<style lang="scss">
	.blocked {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.blocked :global(.section-block) {
		--section-block-notch: var(--color-surface);
	}
	.blocked__notice {
		margin: 0 0 var(--space-base);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-small);
	}
	.blocked__table-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.blocked__table {
		width: 100%;
		min-width: 680px;
		border-collapse: collapse;
		color: var(--color-text);
	}
	.blocked__table th,
	.blocked__table td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}
	.blocked__table thead th {
		background: var(--color-surface--background--subtle);
		color: var(--color-heading);
		font-weight: 700;
	}
	.blocked__table tbody tr:last-child th,
	.blocked__table tbody tr:last-child td {
		border-bottom: 0;
	}
	.blocked__table tbody th strong,
	.blocked__table tbody th small {
		display: block;
	}
	.blocked__table tbody th small {
		margin-top: var(--space-smallest);
		color: var(--color-text--secondary);
		font-weight: 400;
	}
	.blocked__row-action {
		text-align: right;
		white-space: nowrap;
	}
	.blocked__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
	.blocked__form {
		display: grid;
		gap: var(--space-base);
	}
	.blocked__form-lead {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.blocked__form-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.blocked {
			gap: var(--space-base);
		}
		.blocked__form-actions {
			justify-content: flex-start;
		}
	}
</style>
