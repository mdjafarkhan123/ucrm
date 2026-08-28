<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	type OrgPause = {
		id: string;
		reason: string;
		engaged_by_owner_email: string;
		engaged_at: string;
	};
	type PauseResponse = {
		platform_paused: boolean;
		organization_pause: OrgPause | null;
		error?: string;
	};

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const pauseKey = $derived(['jafar', 'organizations', organizationId, 'email-sending-pause']);

	const pauseQuery = createQuery<PauseResponse>(() => ({
		queryKey: pauseKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sending-pause`
			);
			const result = (await response.json()) as PauseResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The organization email pause could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const paused = $derived(Boolean(pauseQuery.data?.organization_pause));
	const platformPaused = $derived(Boolean(pauseQuery.data?.platform_paused));

	let dialogOpen = $state(false);
	let dialogReason = $state('');
	const reasonValid = $derived(dialogReason.trim().length >= 3);
	/** The dialog toggles the opposite of the current state. */
	let dialogEngage = $state(false);

	function openDialog(engage: boolean) {
		dialogEngage = engage;
		dialogReason = '';
		dialogOpen = true;
	}

	const pauseMutation = createMutation<PauseResponse, Error, { engage: boolean; reason: string }>(
		() => ({
			mutationFn: async (body) => {
				const response = await fetch(
					`/api/jafar/organizations/${organizationId}/communications/sending-pause`,
					{
						method: 'POST',
						headers: { 'content-type': 'application/json' },
						body: JSON.stringify(body)
					}
				);
				const result = (await response.json()) as PauseResponse;
				if (!response.ok)
					throw new Error(result.error ?? 'The organization email pause could not be changed.');
				return result;
			},
			onSuccess: async (_data, variables) => {
				dialogOpen = false;
				dialogReason = '';
				toast.success(
					variables.engage
						? 'Email sending is paused for this organization.'
						: 'Email sending has resumed for this organization.'
				);
				await Promise.all([
					queryClient.invalidateQueries({ queryKey: pauseKey }),
					queryClient.invalidateQueries({ queryKey: ['jafar', 'communications', 'email-health'] })
				]);
			},
			onError: (error) => toast.error(error.message)
		})
	);

	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<div class="email-pause">
	<div class="email-pause__heading">
		<div>
			<h3>Email sending</h3>
			<p>
				Hold this organization's outbound email — every class, including quotes, invoices, and
				replies — while a problem is investigated. It cannot be sent around from the contractor
				side.
			</p>
		</div>
		{#if !pauseQuery.isPending && !pauseQuery.isError}
			<Badge status={paused ? 'critical' : 'success'}>{paused ? 'Paused' : 'Sending'}</Badge>
		{/if}
	</div>

	{#if pauseQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading email pause state" />
	{:else if pauseQuery.isError}
		<ErrorState
			title="Email pause state could not be loaded"
			description={pauseQuery.error instanceof Error ? pauseQuery.error.message : 'Try again.'}
			retry={() => pauseQuery.refetch()}
		/>
	{:else}
		{#if platformPaused}
			<p class="email-pause__note">
				The account-wide emergency pause is on, so this organization's email is already held
				regardless of the switch below.
			</p>
		{/if}

		{#if paused && pauseQuery.data?.organization_pause}
			{@const orgPause = pauseQuery.data.organization_pause}
			<dl class="email-pause__detail">
				<div>
					<dt>Reason</dt>
					<dd>{orgPause.reason}</dd>
				</div>
				<div>
					<dt>Paused by</dt>
					<dd>{orgPause.engaged_by_owner_email}</dd>
				</div>
				<div>
					<dt>Since</dt>
					<dd>{formatDateTime(orgPause.engaged_at)}</dd>
				</div>
			</dl>
			<div class="email-pause__actions">
				<Button
					size="small"
					variant="secondary"
					variation="subtle"
					onclick={() => openDialog(false)}>Resume sending</Button
				>
			</div>
		{:else}
			<div class="email-pause__actions">
				<Button size="small" variant="secondary" variation="subtle" onclick={() => openDialog(true)}
					>Pause sending</Button
				>
			</div>
		{/if}
	{/if}
</div>

<ConfirmDialog
	open={dialogOpen}
	title={dialogEngage
		? 'Pause sending for this organization'
		: 'Resume sending for this organization'}
	tone={dialogEngage ? 'critical' : 'success'}
	confirmLabel={dialogEngage ? 'Pause sending' : 'Resume sending'}
	destructive={dialogEngage}
	loading={pauseMutation.isPending}
	confirmDisabled={!reasonValid || pauseMutation.isPending}
	onConfirm={() => {
		if (reasonValid) pauseMutation.mutate({ engage: dialogEngage, reason: dialogReason.trim() });
	}}
	onClose={() => {
		dialogOpen = false;
		dialogReason = '';
	}}
>
	<p>
		{dialogEngage
			? "This organization's queued email waits and is re-checked when you resume. Nothing is cancelled."
			: "Queued email starts flowing again on the outbox worker's next run, each message re-checked first."}
	</p>
	<Textarea
		id="org-email-pause-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={dialogReason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	.email-pause {
		display: grid;
		gap: var(--space-base);
	}

	.email-pause__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		h3 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}

		p {
			margin-top: var(--space-small);
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
		}
	}

	.email-pause__note {
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.email-pause__detail {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;

		> div {
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

	.email-pause__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	@media (max-width: 639px) {
		.email-pause__heading {
			flex-direction: column;
		}

		.email-pause__detail {
			grid-template-columns: 1fr;
		}
	}
</style>
