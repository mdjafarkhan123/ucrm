<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DataTable from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';
	import mailCheckIcon from '@tabler/icons/outline/mail-check.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';

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

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Blocked addresses · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="blocked record-detail--cards">
		<SettingsPageHeader
			title="Blocked addresses"
			description="When a customer's email keeps bouncing or they mark your email as spam, UCRM stops sending to that address to protect your sender reputation. Corrected addresses can be unblocked here."
			icon={mailOffIcon}
			tone="task"
			presentation="communication"
		/>

		<SectionBlock
			tone="inactive"
			title="Blocked email addresses"
			hint="Nothing your team sends reaches these addresses until they are unblocked."
			icon={mailOffIcon}
			level={2}
			class="section-block--flush"
		>
			{#if blockedQuery.isPending}
				<div class="blocked__pad">
					<LoadingSkeleton variant="table" label="Loading blocked addresses" />
				</div>
			{:else if blockedQuery.isError}
				<div class="blocked__pad">
					<ErrorState
						description="Blocked addresses could not be loaded."
						retry={() => blockedQuery.refetch()}
					/>
				</div>
			{:else if blocked.length === 0}
				<div class="blocked__pad">
					<EmptyState
						title="No blocked addresses"
						description="Every customer address your team emails is currently deliverable."
					/>
				</div>
			{:else}
				{#if overCap}
					<p class="blocked__notice" role="status">
						Showing the {blocked.length} most recent of {blockedQuery.data?.blocked_total} blocked addresses.
					</p>
				{/if}
				<DataTable
					variant="card"
					caption="Blocked email addresses"
					columns={[
						{ key: 'address', label: 'Address' },
						{ key: 'why', label: 'Why', width: '170px' },
						{ key: 'blocked', label: 'Blocked', width: '150px' },
						{ key: 'status', label: 'Status', width: '210px' }
					]}
					items={blocked}
					rowId={(address) => address.suppression_id}
				>
					{#snippet row(address)}
						<th scope="row">
							<div class="blocked__address">
								{#if address.client_display_name}
									<Avatar
										id={address.suppression_id}
										name={address.client_display_name}
										size="base"
									/>
								{:else}
									<span class="blocked__address-icon" aria-hidden="true">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
										{@html mailIcon}
									</span>
								{/if}
								<div class="blocked__address-copy">
									<strong>{address.recipient_email}</strong>
									{#if address.client_display_name}
										<small>{address.client_display_name}</small>
									{/if}
								</div>
							</div>
						</th>
						<td>
							<Badge status={reasonTone(address.reason)} dot={false} size="small">
								{reasonLabel(address.reason)}
							</Badge>
						</td>
						<td>{formatDate(address.created_at)}</td>
						<td>
							{#if address.open_request}
								<Badge status="informative" dot={false} size="small">Removal pending review</Badge>
							{:else}
								<Badge status="inactive" dot={false} size="small">Blocked</Badge>
							{/if}
						</td>
					{/snippet}
					{#snippet rowActions(address)}
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
					{/snippet}
				</DataTable>
			{/if}
		</SectionBlock>

		{#if cleared.length > 0}
			<SectionBlock
				tone="inactive"
				title="Recently unblocked"
				icon={mailCheckIcon}
				level={2}
				class="section-block--flush"
			>
				<DataTable
					variant="card"
					caption="Recently unblocked addresses"
					columns={[
						{ key: 'address', label: 'Address' },
						{ key: 'was', label: 'Was blocked for', width: '215px' },
						{ key: 'unblocked', label: 'Unblocked', width: '186px' },
						{ key: 'by', label: 'By', width: '220px' }
					]}
					items={cleared}
					rowId={(address) => address.suppression_id}
				>
					{#snippet row(address)}
						<th scope="row">{address.recipient_email}</th>
						<td>{reasonLabel(address.reason)}</td>
						<td>{formatDate(address.released_at)}</td>
						<td>
							<span class="blocked__by">
								<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
								<span aria-hidden="true"
									>{@html address.released_by_kind === 'organization_admin'
										? usersIcon
										: shieldCheckIcon}</span
								>
								{clearedBy(address.released_by_kind)}
							</span>
						</td>
					{/snippet}
				</DataTable>
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

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.blocked {
		display: flex;
		flex-direction: column;
		gap: 20px;
	}
	/* App-look cards: each block is a white card on the app background. The shared card rules (the
	   `record-detail--cards` context) put the heading, hint and actions inside the card header; the page
	   only restores the framed icon tile, which sits beside the header lines as the approved frame shows. */
	.blocked.record-detail--cards :global(.section-block > .section-block__title) {
		padding-left: 72px;
	}
	.blocked.record-detail--cards :global(.section-block:has(> .section-block__hint)) {
		> :global(.section-block__hint) {
			margin-left: 72px;
		}
	}
	.blocked.record-detail--cards
		:global(.section-block:not(:has(> .section-block__hint)) > .section-block__title) {
		min-height: 76px;
		padding-top: 0;
		padding-bottom: 0;
		box-sizing: border-box;
	}
	.blocked__pad {
		padding: 0 24px 24px;
	}
	.blocked__notice {
		margin: 0 24px var(--space-base);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-small);
	}
	.blocked__address {
		display: flex;
		align-items: center;
		gap: 14px;
	}
	.blocked__address-icon {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-circle);
		color: var(--color-text--secondary);
		background: var(--color-surface--active);
	}
	.blocked__address-icon :global(svg) {
		width: 16px;
		height: 16px;
	}
	.blocked__address-copy {
		display: grid;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.blocked__address-copy strong {
		color: var(--color-heading);
		font-weight: 600;
	}
	.blocked__address-copy small {
		color: var(--color-text--secondary);
		font-size: 13px;
		font-weight: 400;
	}
	.blocked__by {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		color: var(--color-text--secondary);
	}
	.blocked__by :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
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
