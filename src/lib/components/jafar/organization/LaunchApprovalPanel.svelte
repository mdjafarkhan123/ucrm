<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		organizationLaunchApprovalQuery,
		organizationLaunchApprovalUrl,
		organizationPreviewQuery
	} from '$lib/jafar/organization-setup-queries';
	import {
		jafarOnboardingKey,
		jafarOrganizationKey,
		jafarOrganizationLaunchApprovalKey
	} from '$lib/jafar/query-keys';
	import {
		LAUNCH_APPROVAL_METHOD_LABEL,
		LAUNCH_RECORD_REASON_MAX,
		currentLaunchApproval,
		launchApprovalOutcome
	} from '$lib/setup/launch-approval';
	import { formatDateTime } from './format';

	// Client onboarding E4 (plan §6): Jafar asks the final approver named in the client's setup to approve the
	// newest released preview, once Uplift's checks are done (E5 will make Ask wait for its checklist). The approver
	// is emailed a private link; Jafar can send a fresh one, or record an approval given by phone or email with a
	// reason. A newer release cancels an open request and marks an approval replaced. Every request stays listed.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const previews = createQuery(() => organizationPreviewQuery(organizationId));
	const approvals = createQuery(() => organizationLaunchApprovalQuery(organizationId));

	const newest = $derived(previews.data?.released[0] ?? null);
	const current = $derived(currentLaunchApproval(approvals.data ?? []));
	const earlier = $derived((approvals.data ?? []).filter((request) => request !== current));

	let confirmAsk = $state(false);
	let recording = $state(false);
	let reason = $state('');
	let error = $state('');
	let notice = $state('');

	const refresh = () =>
		Promise.all([
			queryClient.invalidateQueries({
				queryKey: jafarOrganizationLaunchApprovalKey(organizationId)
			}),
			queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) }),
			queryClient.invalidateQueries({ queryKey: jafarOnboardingKey })
		]);

	async function post(path: string, body: unknown = {}) {
		const response = await fetch(`${organizationLaunchApprovalUrl(organizationId)}${path}`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
		const result = (await response.json().catch(() => ({}))) as Record<string, unknown> & {
			error?: string;
			field_errors?: Record<string, string>;
			emailed?: boolean;
		};
		if (!response.ok)
			throw new Error(
				Object.values(result.field_errors ?? {})[0] ??
					result.error ??
					'That could not be saved. Try again.'
			);
		return result;
	}

	const emailNote = (emailed: boolean | undefined, sent: string) =>
		emailed === false ? `${sent} The email could not be queued — use Send the link again.` : sent;

	const ask = createMutation(() => ({
		mutationFn: () => post('', { version: newest!.version }),
		onMutate: () => ((error = ''), (notice = '')),
		onSuccess: (result) => {
			confirmAsk = false;
			notice =
				result.status === 'requested'
					? emailNote(result.emailed, 'Asked. The approver has been emailed a private link.')
					: 'Already asked.';
		},
		onError: (cause) => {
			confirmAsk = false;
			error = cause.message;
		},
		onSettled: refresh
	}));

	const resend = createMutation(() => ({
		mutationFn: () => post('/resend'),
		onMutate: () => ((error = ''), (notice = '')),
		onSuccess: (result) =>
			(notice = emailNote(
				result.emailed,
				'A fresh link was emailed. The earlier link stops working.'
			)),
		onError: (cause) => (error = cause.message),
		onSettled: refresh
	}));

	const record = createMutation(() => ({
		mutationFn: () => post('/record', { version: current!.version, reason: reason.trim() }),
		onMutate: () => ((error = ''), (notice = '')),
		onSuccess: (result) => {
			recording = false;
			reason = '';
			notice = emailNote(result.emailed, 'Approval recorded. The receipt was emailed.');
		},
		onError: (cause) => {
			recording = false;
			error = cause.message;
		},
		onSettled: refresh
	}));

	const busy = $derived(ask.isPending || resend.isPending || record.isPending);
</script>

{#if previews.isPending || approvals.isPending}
	<LoadingSkeleton variant="card" label="Loading launch approval" />
{:else if previews.isError || approvals.isError}
	<ErrorState
		title="Launch approval could not be loaded"
		description={(previews.error ?? approvals.error)?.message}
		retry={() => Promise.all([previews.refetch(), approvals.refetch()])}
	/>
{:else if newest || current}
	<SectionBlock title="Launch approval" icon={rocketIcon}>
		<div class="launch-panel">
			{#if notice}<Banner type="success">{notice}</Banner>{/if}
			{#if error}<Banner type="error">{error}</Banner>{/if}

			{#if current?.status === 'approved' && current.approved_at}
				<div class="launch-panel__state">
					<StatusBadge status="success">Approved</StatusBadge>
					<p>
						<strong>{current.approved_by_name}</strong> ({current.approved_by_email}) approved
						version {current.version} on {formatDateTime(
							current.approved_at
						)}{current.approval_method
							? `, ${LAUNCH_APPROVAL_METHOD_LABEL[current.approval_method]}`
							: ''}.
					</p>
					<blockquote class="launch-panel__wording">{current.approval_wording}</blockquote>
					{#if current.recorded_reason}
						<p class="launch-panel__muted">How it was given: {current.recorded_reason}</p>
					{/if}
					<p class="launch-panel__muted">
						Releasing a newer preview marks this approval replaced, and you ask again.
					</p>
				</div>
			{:else if current?.status === 'open'}
				<div class="launch-panel__state">
					<StatusBadge status={current.not_yet_at ? 'warning' : 'informative'}
						>{launchApprovalOutcome(current)}</StatusBadge
					>
					<p>
						Asked {formatDateTime(current.requested_at)} for version {current.version}. Sent to
						<strong>{current.approver_name}</strong> ({current.approver_email}); the link was
						emailed
						{formatDateTime(current.link_sent_at)} and works until {formatDateTime(
							current.link_expires_at
						)}.
					</p>
					{#if current.not_yet_at}
						<Banner type="warning">
							{current.not_yet_by_name ?? current.approver_name} said not yet on
							{formatDateTime(current.not_yet_at)}{current.not_yet_note
								? `: “${current.not_yet_note}”`
								: '.'} Talk to them in Support; they can still approve with the same link.
						</Banner>
					{/if}
					<div class="launch-panel__actions">
						<Button
							variant="secondary"
							disabled={busy}
							loading={resend.isPending}
							onclick={() => resend.mutate()}>Send the link again</Button
						>
						<Button
							variant="tertiary"
							disabled={busy}
							onclick={() => {
								error = '';
								recording = true;
							}}>Record an approval given another way</Button
						>
					</div>
				</div>
			{:else if newest?.notes_sent_at}
				<p class="launch-panel__muted">
					They sent corrections on version {newest.version}. Release a new version, then ask for
					launch approval on it.
				</p>
			{:else if newest}
				<p class="launch-panel__muted">
					When Uplift’s launch checks are done, ask the final approver named in their setup to
					approve version {newest.version}. They are emailed a private link that needs no login.
				</p>
				<div class="launch-panel__actions">
					<Button disabled={busy} onclick={() => (confirmAsk = true)}
						>Ask for launch approval</Button
					>
				</div>
			{/if}

			{#if earlier.length}
				<details class="launch-panel__history">
					<summary>Earlier requests ({earlier.length})</summary>
					<ul>
						{#each earlier as request (request.id)}
							<li>
								<strong>Version {request.version}</strong> — {launchApprovalOutcome(request)}. Asked {formatDateTime(
									request.requested_at
								)}, sent to {request.approver_name}{request.approved_at
									? `; approved ${formatDateTime(request.approved_at)} by ${request.approved_by_name}`
									: ''}{request.closed_at ? `; closed ${formatDateTime(request.closed_at)}` : ''}.
							</li>
						{/each}
					</ul>
				</details>
			{/if}
		</div>
	</SectionBlock>

	<ConfirmDialog
		open={confirmAsk}
		title="Ask for launch approval?"
		confirmLabel="Ask and email the link"
		loading={ask.isPending}
		onConfirm={() => ask.mutate()}
		onClose={() => (confirmAsk = false)}
	>
		<p>
			The final approver named in their newest send is emailed a private link to approve version
			{newest?.version}. Ask only once Uplift’s launch checks are done.
		</p>
	</ConfirmDialog>

	<ConfirmDialog
		open={recording}
		title="Record an approval given another way"
		confirmLabel="Record approval"
		loading={record.isPending}
		confirmDisabled={!reason.trim()}
		onConfirm={() => record.mutate()}
		onClose={() => (recording = false)}
	>
		<p>
			Only for a clear yes from {current?.approver_name} to version {current?.version}, given by
			phone or email. The client sees it as recorded by Uplift.
		</p>
		<Textarea
			id="launch-record-reason"
			label="How was it given?"
			placeholder="For example: approved on a phone call on 5 October"
			rows={3}
			maxlength={LAUNCH_RECORD_REASON_MAX}
			bind:value={reason}
		/>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.launch-panel {
		display: grid;
		gap: var(--space-base);

		&__state {
			display: grid;
			justify-items: start;
			gap: var(--space-small);

			p {
				margin: 0;
			}
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__wording {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-success);
			background: var(--color-surface--background);
			font-style: italic;
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__history {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			summary {
				cursor: pointer;
			}

			ul {
				display: grid;
				gap: var(--space-smaller);
				margin: var(--space-small) 0 0;
				padding-left: var(--space-base);
			}
		}
	}
</style>
