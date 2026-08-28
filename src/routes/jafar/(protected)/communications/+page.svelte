<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import playerPauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import EmailReputationPlatformControls from '$lib/components/jafar/EmailReputationPlatformControls.svelte';
	import EmailSendingCapacityControls from '$lib/components/jafar/EmailSendingCapacityControls.svelte';
	import EmailSuppressionRemovalQueue from '$lib/components/jafar/EmailSuppressionRemovalQueue.svelte';
	import MessageRecoveryQueue from '$lib/components/jafar/MessageRecoveryQueue.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	type PlatformPause = {
		id: string;
		reason: string;
		engaged_by: string;
		engaged_at: string;
	} | null;
	type OrgPause = {
		id: string;
		organization_id: string;
		organization_name: string;
		reason: string;
		engaged_by: string;
		engaged_at: string;
	};
	type Health = {
		platform_pause: PlatformPause;
		organization_pauses: OrgPause[];
		held_email_count: number;
		queued_email_count: number;
	};
	type HealthResponse = { health: Health; error?: string };

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const healthKey = ['jafar', 'communications', 'email-health'] as const;

	const healthQuery = createQuery<HealthResponse>(() => ({
		queryKey: healthKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/email-health');
			const result = (await response.json()) as HealthResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'Email sending health could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const health = $derived(healthQuery.data?.health ?? null);
	const platformPaused = $derived(Boolean(health?.platform_pause));
	const orgPauses = $derived(health?.organization_pauses ?? []);

	type DialogMode = 'engage-platform' | 'release-platform' | 'release-org' | null;
	let dialogMode = $state<DialogMode>(null);
	let dialogOrg = $state<OrgPause | null>(null);
	let dialogReason = $state('');
	const reasonValid = $derived(dialogReason.trim().length >= 3);

	function openDialog(mode: Exclude<DialogMode, null>, org: OrgPause | null = null) {
		dialogMode = mode;
		dialogOrg = org;
		dialogReason = '';
	}
	function closeDialog() {
		dialogMode = null;
		dialogOrg = null;
		dialogReason = '';
	}

	function applyHealth(next: Health) {
		queryClient.setQueryData<HealthResponse>(healthKey, { health: next });
	}

	const platformMutation = createMutation<Health, Error, { engage: boolean; reason: string }>(
		() => ({
			mutationFn: async (body) => {
				const response = await fetch('/api/jafar/communications/email-health', {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				});
				const result = (await response.json()) as HealthResponse;
				if (!response.ok)
					throw new Error(result.error ?? 'The platform email pause could not be changed.');
				return result.health;
			},
			onSuccess: (next, variables) => {
				applyHealth(next);
				closeDialog();
				toast.success(
					variables.engage ? 'All email sending is paused.' : 'Email sending has resumed.'
				);
			},
			onError: (error) => toast.error(error.message)
		})
	);

	const orgReleaseMutation = createMutation<
		Health,
		Error,
		{ organizationId: string; reason: string }
	>(() => ({
		mutationFn: async ({ organizationId, reason }) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sending-pause`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ engage: false, reason })
				}
			);
			const result = (await response.json()) as HealthResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The organization email pause could not be changed.');
			return result.health;
		},
		onSuccess: (next) => {
			applyHealth(next);
			closeDialog();
			toast.success('Sending has resumed for that organization.');
		},
		onError: (error) => toast.error(error.message)
	}));

	const mutationPending = $derived(platformMutation.isPending || orgReleaseMutation.isPending);

	function confirmDialog() {
		if (!reasonValid) return;
		const reason = dialogReason.trim();
		if (dialogMode === 'engage-platform') platformMutation.mutate({ engage: true, reason });
		else if (dialogMode === 'release-platform') platformMutation.mutate({ engage: false, reason });
		else if (dialogMode === 'release-org' && dialogOrg)
			orgReleaseMutation.mutate({ organizationId: dialogOrg.organization_id, reason });
	}

	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	const dialogCopy = $derived.by(() => {
		if (dialogMode === 'engage-platform')
			return {
				title: 'Pause all email sending',
				tone: 'critical' as const,
				confirmLabel: 'Pause all sending',
				destructive: true,
				body: 'Nothing leaves the outbox for any organization while this is on — including requested quotes, invoices, receipts, and replies. Queued messages wait and are re-checked when you resume.'
			};
		if (dialogMode === 'release-platform')
			return {
				title: 'Resume email sending',
				tone: 'success' as const,
				confirmLabel: 'Resume sending',
				destructive: false,
				body: 'The outbox worker starts claiming queued messages again on its next run. Each message is fully re-checked before it sends.'
			};
		return {
			title: 'Resume sending for this organization',
			tone: 'success' as const,
			confirmLabel: 'Resume sending',
			destructive: false,
			body: `${dialogOrg?.organization_name ?? 'This organization'}'s queued email starts flowing again on the next worker run, each message re-checked first.`
		};
	});
</script>

<svelte:head>
	<title>Email safety · Control Room</title>
</svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="email-safety">
	<header class="email-safety__header">
		<p class="email-safety__eyebrow">Email safety</p>
		<h1>Email sending</h1>
		<p class="email-safety__description">
			The master switch for outbound email. Pause everything in an emergency, or hold one
			organization while you look into a problem. Contractors cannot send around a pause.
		</p>
	</header>

	{#if healthQuery.isPending}
		<LoadingSkeleton variant="table" rows={4} label="Loading email sending health" />
	{:else if healthQuery.isError}
		<ErrorState
			title="Email sending health could not be loaded"
			description={healthQuery.error instanceof Error ? healthQuery.error.message : 'Try again.'}
			retry={() => healthQuery.refetch()}
		/>
	{:else if health}
		<section class="email-safety__summary" aria-label="Email sending summary">
			<KpiCard
				label="Platform sending"
				value={platformPaused ? 'Paused' : 'Active'}
				note={platformPaused ? 'Emergency pause is on' : 'Outbox worker running'}
				icon={platformPaused ? playerPauseIcon : mailIcon}
				tone={platformPaused ? 'critical' : 'success'}
				variant="compact"
			/>
			<KpiCard
				label="Organizations paused"
				value={String(orgPauses.length)}
				note="Held individually"
				icon={buildingIcon}
				tone={orgPauses.length > 0 ? 'warning' : 'default'}
				variant="compact"
			/>
			<KpiCard
				label="Messages held"
				value={String(health.held_email_count)}
				note="Waiting on a pause"
				icon={alertIcon}
				tone={health.held_email_count > 0 ? 'warning' : 'default'}
				variant="compact"
			/>
			<KpiCard
				label="Queued messages"
				value={String(health.queued_email_count)}
				note="In the outbox now"
				icon={mailIcon}
				variant="compact"
			/>
		</section>

		<Card class="email-safety__panel">
			<div class="email-safety__panel-head">
				<div>
					<h2>Account-wide emergency pause</h2>
					<p>Stops every send for every organization until you resume it.</p>
				</div>
				<Badge status={platformPaused ? 'critical' : 'success'}>
					{platformPaused ? 'Paused' : 'Active'}
				</Badge>
			</div>

			{#if platformPaused && health.platform_pause}
				<dl class="email-safety__detail">
					<div>
						<dt>Reason</dt>
						<dd>{health.platform_pause.reason}</dd>
					</div>
					<div>
						<dt>Paused by</dt>
						<dd>{health.platform_pause.engaged_by}</dd>
					</div>
					<div>
						<dt>Since</dt>
						<dd>{formatDateTime(health.platform_pause.engaged_at)}</dd>
					</div>
				</dl>
				<div class="email-safety__panel-actions">
					<Button variation="work" onclick={() => openDialog('release-platform')}>
						Resume sending
					</Button>
				</div>
			{:else}
				<div class="email-safety__panel-actions">
					<Button variation="destructive" onclick={() => openDialog('engage-platform')}>
						Pause all sending
					</Button>
				</div>
			{/if}
		</Card>

		<Card class="email-safety__panel">
			<div class="email-safety__panel-head">
				<div>
					<h2>Organizations paused</h2>
					<p>Engage a single-organization pause from that organization's detail page.</p>
				</div>
			</div>

			{#if orgPauses.length === 0}
				<EmptyState
					title="No organization is paused"
					description="Every organization's email is following the account-wide state."
				/>
			{:else}
				<div class="email-safety__table-wrap">
					<table class="email-safety__table">
						<thead>
							<tr>
								<th scope="col">Organization</th>
								<th scope="col">Reason</th>
								<th scope="col">Paused by</th>
								<th scope="col">Since</th>
								<th scope="col"><span class="email-safety__sr-only">Resume</span></th>
							</tr>
						</thead>
						<tbody>
							{#each orgPauses as pause (pause.id)}
								<tr>
									<th scope="row">
										<a href={resolve(`/jafar/organizations/${pause.organization_id}`)}>
											{pause.organization_name}
										</a>
									</th>
									<td>{pause.reason}</td>
									<td>{pause.engaged_by}</td>
									<td>{formatDateTime(pause.engaged_at)}</td>
									<td class="email-safety__row-action">
										<Button
											size="small"
											variant="secondary"
											variation="subtle"
											onclick={() => openDialog('release-org', pause)}
										>
											Resume
										</Button>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</Card>
	{/if}

	<EmailReputationPlatformControls />

	<EmailSuppressionRemovalQueue />

	<EmailSendingCapacityControls />

	<MessageRecoveryQueue />
</main>
<!-- eslint-enable svelte/no-at-html-tags -->

<ConfirmDialog
	open={dialogMode !== null}
	title={dialogCopy.title}
	tone={dialogCopy.tone}
	confirmLabel={dialogCopy.confirmLabel}
	destructive={dialogCopy.destructive}
	loading={mutationPending}
	confirmDisabled={!reasonValid || mutationPending}
	onConfirm={confirmDialog}
	onClose={closeDialog}
>
	<p>{dialogCopy.body}</p>
	<Textarea
		id="email-pause-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={dialogReason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	.email-safety {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.email-safety h1,
	.email-safety h2,
	.email-safety p {
		margin: 0;
	}

	.email-safety h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.email-safety h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}

	.email-safety__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.email-safety__eyebrow {
		margin-bottom: var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.email-safety__description {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.email-safety__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.email-safety :global(.email-safety__panel) {
		display: grid;
		gap: var(--space-base);
	}

	.email-safety__panel-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		p {
			margin-top: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
	}

	.email-safety__detail {
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

	.email-safety__panel-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.email-safety__table-wrap {
		overflow-x: auto;
	}

	.email-safety__table {
		width: 100%;
		min-width: 640px;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);

		th,
		td {
			padding: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
			text-align: left;
			vertical-align: top;
		}

		thead th {
			color: var(--color-text--secondary);
			font-weight: 700;
			white-space: nowrap;
		}

		tbody th {
			color: var(--color-heading);
			font-weight: 700;
		}

		tbody a {
			color: var(--color-interactive);
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}

		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}
	}

	.email-safety__row-action {
		text-align: right;
		white-space: nowrap;
	}

	.email-safety__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 1200px) {
		.email-safety__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 900px) {
		.email-safety__detail {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 639px) {
		.email-safety h1 {
			font-size: 28px;
		}

		.email-safety__summary {
			grid-template-columns: 1fr;
		}

		.email-safety__panel-head {
			flex-direction: column;
		}
	}
</style>
