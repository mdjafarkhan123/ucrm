<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import RecordCard from '$lib/components/layout/RecordCard.svelte';
	import ProfitFeatureCard from '$lib/components/work/ProfitFeatureCard.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		controlInquiryEnrollment,
		fetchInquiryAutomation,
		inquiryAutomationKey,
		type InquiryAutomationError,
		type InquiryEnrollment,
		type InquiryRecord
	} from '$lib/automation/inquiry-enrollments';
	import type { EnrollmentControl } from '$lib/quotes/automation';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import playIcon from '@tabler/icons/outline/player-play.svg?raw';
	import skipIcon from '@tabler/icons/outline/player-skip-forward.svg?raw';
	import stopIcon from '@tabler/icons/outline/player-stop.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import adjustmentsIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';

	// CRM launch readiness Part 4 Stage 6: a website inquiry's automatic follow-up, shown on the Request it became or
	// its chat conversation (HighLevel's contact Workflows panel). Staff see whether the reply is waiting, paused and
	// why, sent, or stopped and why, and can Pause, Resume, Skip or Stop it. Like the Quote card, nothing loads with
	// the page: it fetches once the pointer reaches it, and hides itself for a viewer without Automation access.
	let {
		record,
		customerName = null
	}: {
		record: InquiryRecord;
		/** Classic: whose messages the card counts ("Messages sent to Daniel"). */
		customerName?: string | null;
	} = $props();

	const classic = $derived(page.data.presentation === 'classic');

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let warm = $state(false);

	const query = createQuery(() => ({
		queryKey: inquiryAutomationKey(record),
		queryFn: () => fetchInquiryAutomation(record),
		enabled: warm,
		staleTime: 15_000,
		retry: false
	}));

	const accessDenied = $derived.by(() => {
		const reason = (query.error as InquiryAutomationError | null)?.reason;
		return reason === 'not_included' || reason === 'permission_denied';
	});

	const enrollments = $derived<InquiryEnrollment[]>(query.data?.enrollments ?? []);
	const canControl = $derived(Boolean(query.data?.can_control));

	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		hour: 'numeric',
		minute: '2-digit'
	});

	const STATE: Record<
		string,
		{ tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative'; label: string }
	> = {
		active: { tone: 'informative', label: 'Waiting' },
		paused: { tone: 'warning', label: 'Paused' },
		completed: { tone: 'success', label: 'Finished' },
		stopped: { tone: 'inactive', label: 'Stopped' },
		failed: { tone: 'critical', label: 'Needs attention' }
	};

	// Engine codes in plain English; anything else (a staff member's typed stop reason) shows as written.
	const STOP_REASON: Record<string, string> = {
		staff_replied: 'Stopped because someone on your team replied',
		inquiry_not_found: 'Stopped because the inquiry was removed',
		no_customer_record: 'Stopped because there was no customer to reply to yet',
		no_email_address:
			'Stopped because there was no email address to reply to, and texting was not possible',
		invalid_email_content: 'Stopped because the reply had no message',
		recipe_not_active: 'Stopped because the automation was turned off',
		enrollment_expired: 'Stopped because it reached the maximum follow-up length',
		automations_not_entitled: 'Stopped because automations are not included in the current plan',
		automation_suspended: 'Stopped because automations are paused for this account'
	};

	const HELD_REASON: Record<string, string> = {
		email_sender_not_ready: 'Waiting for your email sending to be set up, then it will try again.',
		action_not_available: 'This step cannot run. Skip it or stop the follow-up.'
	};

	function detailLine(enrollment: InquiryEnrollment): string {
		if (enrollment.state === 'paused') {
			return enrollment.paused_reason === 'customer_reply'
				? 'The customer replied, so the next message is on hold. Resume to send it anyway.'
				: 'Paused by your team. Resume to continue.';
		}
		if (enrollment.state === 'active' && enrollment.next_due_at)
			return `Next step ${dateTimeFormat.format(new Date(enrollment.next_due_at))}`;
		const sent = enrollment.customer_messages_sent;
		return `${sent} message${sent === 1 ? '' : 's'} sent`;
	}

	// classic.pen "Follow-up card": the newest follow-up as the page's dark featured card, any older ones as
	// a line under it. Loading, errors and "none" stay a small plain card.
	const STATE_ICON: Record<string, string> = {
		active: hourglassIcon,
		paused: pauseIcon,
		completed: checkIcon,
		stopped: stopIcon,
		failed: alertIcon
	};
	const lead = $derived(enrollments[0]);
	const older = $derived(enrollments.slice(1));
	const firstName = $derived(customerName?.trim().split(/\s+/)[0] || 'the customer');
	const leadSubline = $derived.by(() => {
		if (!lead) return '';
		if (lead.state === 'stopped' && lead.stop_reason)
			return STOP_REASON[lead.stop_reason] ?? lead.stop_reason;
		if (lead.state === 'completed') return 'Every step has run';
		return detailLine(lead);
	});

	let pendingId = $state<string | null>(null);
	let stoppingId = $state<string | null>(null);
	let stopReason = $state('');

	async function runControl(enrollmentId: string, control: EnrollmentControl, done: string) {
		if (pendingId) return;
		pendingId = enrollmentId;
		try {
			await controlInquiryEnrollment(enrollmentId, control);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: inquiryAutomationKey(record) }),
				queryClient.invalidateQueries({ queryKey: ['settings', 'automation'] })
			]);
			toast.success(done);
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'That change could not be applied.');
		} finally {
			pendingId = null;
		}
	}

	function menuItems(enrollment: InquiryEnrollment) {
		const disabled = pendingId !== null;
		const id = enrollment.enrollment_id;
		const items = [];
		if (enrollment.state === 'active')
			items.push({
				label: 'Pause',
				icon: pauseIcon,
				disabled,
				onSelect: () => void runControl(id, { action: 'pause' }, 'Follow-up paused')
			});
		if (enrollment.state === 'paused')
			items.push({
				label: 'Resume',
				icon: playIcon,
				disabled,
				onSelect: () => void runControl(id, { action: 'resume' }, 'Follow-up resumed')
			});
		items.push({
			label: 'Skip next step',
			icon: skipIcon,
			disabled,
			onSelect: () => void runControl(id, { action: 'skip' }, 'Next step skipped')
		});
		items.push({
			label: 'Stop',
			icon: stopIcon,
			destructive: true,
			disabled,
			onSelect: () => {
				stopReason = '';
				stoppingId = id;
			}
		});
		return items;
	}

	async function confirmStop() {
		if (!stoppingId) return;
		const reason = stopReason.trim();
		await runControl(
			stoppingId,
			{ action: 'stop', reason: reason || undefined },
			'Follow-up stopped'
		);
		stoppingId = null;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if !accessDenied && classic}
	<div role="presentation" onmouseenter={() => (warm = true)} onfocusin={() => (warm = true)}>
		{#if lead && warm && !query.isPending && !query.isError}
			{@const state = STATE[lead.state] ?? { tone: 'inactive', label: lead.state }}
			<ProfitFeatureCard
				label="Automatic follow-up"
				eyebrow="Automatic follow-up"
				value={lead.recipe_name}
				compact
				chip={{ label: state.label, icon: STATE_ICON[lead.state] ?? hourglassIcon }}
				subline={leadSubline}
				showBar={false}
				parts={[
					{
						key: 'sent',
						label: `Messages sent to ${firstName}`,
						amount: String(lead.customer_messages_sent),
						share: 0,
						percent: null,
						tone: 'none'
					}
				]}
			>
				{#if lead.held_reason && (lead.state === 'active' || lead.state === 'failed')}
					<p class="profit-card__note profit-card__note--warn" role="status">
						{HELD_REASON[lead.held_reason] ?? 'The last try did not go through. It will try again.'}
					</p>
				{/if}
				{#if older.length > 0}
					<p class="profit-card__note">
						Also on this inquiry: {older
							.map((entry) => `${entry.recipe_name} (${STATE[entry.state]?.label ?? entry.state})`)
							.join(', ')}
					</p>
				{/if}
				{#if canControl && (lead.state === 'active' || lead.state === 'paused')}
					<div class="inquiry-automation__controls">
						<DropdownMenu
							items={menuItems(lead)}
							triggerLabel="Follow-up actions"
							triggerClass="inquiry-automation__control"
							disabled={pendingId !== null}
						>
							{#snippet trigger()}
								<span aria-hidden="true">{@html adjustmentsIcon}</span>
								{lead.state === 'paused' ? 'Resume, skip or stop' : 'Pause, skip or stop'}
							{/snippet}
						</DropdownMenu>
					</div>
				{/if}
			</ProfitFeatureCard>
		{:else}
			<RecordCard
				title="Automatic follow-up"
				subtitle="Replies sent for you"
				size="rail"
				id="request-follow-up"
			>
				<div class="inquiry-automation__pad">
					{#if !warm || query.isPending}
						<LoadingSkeleton variant="text" label="Loading automatic follow-up" />
					{:else if query.isError}
						<ErrorState
							description="Automation history could not be loaded."
							retry={() => query.refetch()}
						/>
					{:else}
						<p class="inquiry-automation__empty">No automation is following up on this inquiry.</p>
					{/if}
				</div>
			</RecordCard>
		{/if}
	</div>
{:else if !accessDenied}
	<div role="presentation" onmouseenter={() => (warm = true)} onfocusin={() => (warm = true)}>
		<RailCard title="Automatic follow-up" icon={robotIcon}>
			{#if !warm || query.isPending}
				<LoadingSkeleton variant="table" rows={2} label="Loading automatic follow-up" />
			{:else if query.isError}
				<ErrorState
					description="Automation history could not be loaded."
					retry={() => query.refetch()}
				/>
			{:else if enrollments.length === 0}
				<EmptyState
					icon={robotIcon}
					title="No automatic follow-up"
					description="No automation is following up on this inquiry."
				/>
			{:else}
				<ul class="inquiry-automation__list">
					{#each enrollments as enrollment (enrollment.enrollment_id)}
						{@const state = STATE[enrollment.state] ?? {
							tone: 'inactive',
							label: enrollment.state
						}}
						<li class="inquiry-automation__row">
							<div class="inquiry-automation__body">
								<span class="inquiry-automation__name">{enrollment.recipe_name}</span>
								<StatusBadge status={state.tone}>{state.label}</StatusBadge>
								<p class="inquiry-automation__meta">{detailLine(enrollment)}</p>
								{#if enrollment.state === 'stopped' && enrollment.stop_reason}
									<p class="inquiry-automation__meta">
										{STOP_REASON[enrollment.stop_reason] ?? enrollment.stop_reason}
									</p>
								{/if}
								{#if enrollment.held_reason && (enrollment.state === 'active' || enrollment.state === 'failed')}
									<p class="inquiry-automation__held" role="status">
										{HELD_REASON[enrollment.held_reason] ??
											'The last try did not go through. It will try again.'}
									</p>
								{/if}
							</div>
							{#if canControl && (enrollment.state === 'active' || enrollment.state === 'paused')}
								<DropdownMenu
									items={menuItems(enrollment)}
									triggerLabel="Follow-up actions"
									disabled={pendingId !== null}
								/>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</RailCard>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

{#if stoppingId}
	<ConfirmDialog
		open
		title="Stop this follow-up?"
		tone="critical"
		confirmLabel="Stop follow-up"
		destructive
		loading={pendingId !== null}
		onConfirm={confirmStop}
		onClose={() => (stoppingId = null)}
	>
		<p>
			No more automatic messages will go to this customer for this inquiry. Messages already sent
			are not recalled.
		</p>
		<Textarea
			id="inquiry-stop-reason"
			label="Reason (optional)"
			rows={3}
			maxlength={200}
			bind:value={stopReason}
		/>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.inquiry-automation {
		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small);
			padding-bottom: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				padding-bottom: 0;
				border-bottom: 0;
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-smaller);
			min-width: 0;
		}

		&__name {
			max-width: 100%;
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__meta {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__pad {
			padding: 0 20px 18px;
		}

		&__empty {
			margin: 0;
			color: var(--classic2-secondary);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-label);
		}

		&__controls {
			display: flex;
		}

		&__held {
			margin: 0;
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
		}
	}

	// The Classic card's white button sits in ProfitFeatureCard's markup, so it is styled globally by class.
	:global(.inquiry-automation__control) {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		height: 34px;
		padding: 0 14px;
		border: 0;
		border-radius: var(--classic2-radius-control);
		background: var(--classic2-white);
		color: var(--classic2-on-white);
		font-family: var(--classic2-font);
		font-size: var(--classic2-font-label);
		font-weight: 600;
		cursor: pointer;
	}

	:global(.inquiry-automation__control svg) {
		width: 16px;
		height: 16px;
	}

	:global(.inquiry-automation__control:hover:not(:disabled)) {
		background: var(--classic2-feature-label);
	}

	:global(.inquiry-automation__control:focus-visible) {
		outline: 2px solid var(--classic2-white);
		outline-offset: 2px;
	}

	:global(.inquiry-automation__control:disabled) {
		opacity: 0.6;
		cursor: not-allowed;
	}
</style>
