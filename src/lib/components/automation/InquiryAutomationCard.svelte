<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
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
	import stopIcon from '@tabler/icons/outline/circle-square.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import finishedIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import mailAlertIcon from '@tabler/icons/outline/mail-exclamation.svg?raw';

	// CRM launch readiness Part 4 Stage 6: a website inquiry's automatic follow-up, shown on the Request it became or
	// its chat conversation (HighLevel's contact Workflows panel). Staff see whether the reply is waiting, paused and
	// why, sent, or stopped and why, and can Pause, Resume, Skip or Stop it. Like the Quote card, nothing loads with
	// the page: it fetches once the pointer reaches it, and hides itself for a viewer without Automation access.
	let { record }: { record: InquiryRecord } = $props();

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

	// A follow-up still running gets the big panel; finished and stopped ones are one line each under EARLIER.
	const RUNNING = new Set(['active', 'paused', 'failed']);
	const running = $derived(enrollments.filter((enrollment) => RUNNING.has(enrollment.state)));
	const earlier = $derived(enrollments.filter((enrollment) => !RUNNING.has(enrollment.state)));

	// The panel takes the colour of what it needs: planned is blue, on hold is amber, failed is red. A stuck
	// step stays blue with an amber strip inside, so the strip never blends into its panel.
	function panelTone(enrollment: InquiryEnrollment) {
		if (enrollment.state === 'failed') return 'critical';
		if (enrollment.state === 'paused') return 'warning';
		return 'informative';
	}

	// The panel's big line and the words under it.
	function when(enrollment: InquiryEnrollment): { kicker: string; big: string; under?: string } | null {
		if (enrollment.state === 'paused')
			return enrollment.paused_reason === 'customer_reply'
				? {
						kicker: 'On hold',
						big: 'The customer replied',
						under: 'The next message is on hold. Resume to send it anyway.'
					}
				: { kicker: 'On hold', big: 'Paused by your team', under: 'Resume to continue.' };
		if (enrollment.state === 'failed')
			return {
				kicker: 'Last try',
				big: 'The last try did not go through',
				under: (enrollment.held_reason && HELD_REASON[enrollment.held_reason]) || 'It will try again.'
			};
		if (enrollment.next_due_at)
			return { kicker: 'Next step', big: dateTimeFormat.format(new Date(enrollment.next_due_at)) };
		return null;
	}

	function sentLine(enrollment: InquiryEnrollment) {
		const sent = enrollment.customer_messages_sent;
		return `${sent} message${sent === 1 ? '' : 's'} sent`;
	}

	function earlierLine(enrollment: InquiryEnrollment) {
		if (enrollment.state === 'stopped' && enrollment.stop_reason)
			return STOP_REASON[enrollment.stop_reason] ?? enrollment.stop_reason;
		return sentLine(enrollment);
	}

	// One filled circle per message sent, kept to a row's width.
	const TRAIL_MAX = 6;

	let pendingId = $state<string | null>(null);
	let pendingAction = $state<EnrollmentControl['action'] | null>(null);
	let stoppingId = $state<string | null>(null);
	let stopReason = $state('');

	async function runControl(enrollmentId: string, control: EnrollmentControl, done: string) {
		if (pendingId) return;
		pendingId = enrollmentId;
		pendingAction = control.action;
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
			pendingAction = null;
		}
	}

	function askStop(enrollmentId: string) {
		stopReason = '';
		stoppingId = enrollmentId;
	}

	const stopping = $derived(enrollments.find((enrollment) => enrollment.enrollment_id === stoppingId));

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
{#if !accessDenied}
	<div role="presentation" onmouseenter={() => (warm = true)} onfocusin={() => (warm = true)}>
		<RailCard
			tone="conversation"
			title="Automatic follow-up"
			description="Messages sent for you"
			icon={robotIcon}
		>
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
				<div class="inquiry-automation">
					{#each running as enrollment (enrollment.enrollment_id)}
						{@const state = STATE[enrollment.state] ?? { tone: 'inactive', label: enrollment.state }}
						{@const tone = panelTone(enrollment)}
						{@const time = when(enrollment)}
						{@const busy = pendingId === enrollment.enrollment_id}
						<section
							class="inquiry-automation__panel tinted-surface"
							style:--panel-tone={`var(--color-${tone})`}
							style:--panel-surface={`var(--color-${tone}--surface)`}
							style:--panel-edge={`var(--color-${tone}--surface-edge)`}
							style:--panel-on={`var(--color-${tone}--onSurface)`}
							aria-label={enrollment.recipe_name}
						>
							<div class="inquiry-automation__top">
								<span class="inquiry-automation__name">{enrollment.recipe_name}</span>
								<StatusBadge status={state.tone} outlined>{state.label}</StatusBadge>
							</div>

							{#if time}
								<div class="inquiry-automation__when">
									<span class="inquiry-automation__kicker">{time.kicker}</span>
									<span
										class="inquiry-automation__big"
										class:inquiry-automation__big--reason={Boolean(time.under)}>{time.big}</span
									>
									{#if time.under}<span class="inquiry-automation__under">{time.under}</span>{/if}
								</div>
							{/if}

							<div class="inquiry-automation__trail">
								<span class="inquiry-automation__steps" aria-hidden="true">
									{#each { length: Math.min(enrollment.customer_messages_sent, TRAIL_MAX) }, index (index)}
										{#if index > 0}<span class="inquiry-automation__link"></span>{/if}
										<span class="inquiry-automation__sent">{@html checkIcon}</span>
									{/each}
									{#if enrollment.state !== 'failed'}
										{#if enrollment.customer_messages_sent > 0}<span
												class="inquiry-automation__link"
											></span>{/if}
										<span class="inquiry-automation__next"></span>
									{/if}
								</span>
								<span class="inquiry-automation__count">{sentLine(enrollment)}</span>
							</div>

							{#if enrollment.state === 'active' && enrollment.held_reason}
								<p class="inquiry-automation__strip" role="status">
									<span aria-hidden="true"
										>{@html enrollment.held_reason === 'email_sender_not_ready'
											? mailAlertIcon
											: alertIcon}</span
									>
									{HELD_REASON[enrollment.held_reason] ??
										'The last try did not go through. It will try again.'}
								</p>
							{/if}

							{#if canControl && (enrollment.state === 'active' || enrollment.state === 'paused')}
								<div class="inquiry-automation__actions">
									{#if enrollment.state === 'active'}
										<Button
											variant="secondary"
											size="small"
											loading={busy && pendingAction === 'pause'}
											disabled={pendingId !== null && !(busy && pendingAction === 'pause')}
											onclick={() =>
												void runControl(enrollment.enrollment_id, { action: 'pause' }, 'Follow-up paused')}
										>
											{@html pauseIcon}Pause
										</Button>
									{:else}
										<Button
											variant="primary"
											size="small"
											loading={busy && pendingAction === 'resume'}
											disabled={pendingId !== null && !(busy && pendingAction === 'resume')}
											onclick={() =>
												void runControl(
													enrollment.enrollment_id,
													{ action: 'resume' },
													'Follow-up resumed'
												)}
										>
											{@html playIcon}Resume
										</Button>
									{/if}
									<Button
										variant="secondary"
										size="small"
										label="Skip next step"
										loading={busy && pendingAction === 'skip'}
										disabled={pendingId !== null && !(busy && pendingAction === 'skip')}
										onclick={() =>
											void runControl(enrollment.enrollment_id, { action: 'skip' }, 'Next step skipped')}
									>
										{@html skipIcon}Skip
									</Button>
									<Button
										variant="secondary"
										variation="destructive"
										size="small"
										disabled={pendingId !== null}
										onclick={() => askStop(enrollment.enrollment_id)}
									>
										{@html stopIcon}Stop
									</Button>
								</div>
							{/if}
						</section>
					{/each}

					{#if earlier.length > 0}
						<div class="inquiry-automation__earlier" class:inquiry-automation__earlier--lined={running.length > 0}>
							<span class="inquiry-automation__overline">Earlier</span>
							<ul class="inquiry-automation__list">
								{#each earlier as enrollment (enrollment.enrollment_id)}
									{@const state = STATE[enrollment.state] ?? { tone: 'inactive', label: enrollment.state }}
									<li class="inquiry-automation__row">
										<IconTile
											icon={enrollment.state === 'completed' ? finishedIcon : stopIcon}
											tone={state.tone}
											size={24}
										/>
										<div class="inquiry-automation__row-words">
											<span class="inquiry-automation__row-name">{enrollment.recipe_name}</span>
											<span class="inquiry-automation__row-line">{earlierLine(enrollment)}</span>
										</div>
										<StatusBadge status={state.tone} size="small">{state.label}</StatusBadge>
									</li>
								{/each}
							</ul>
						</div>
					{/if}
				</div>
			{/if}
		</RailCard>
	</div>
{/if}

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
		{#if stopping}
			<div class="inquiry-automation__slip">
				<IconTile icon={robotIcon} tone="conversation" size={32} />
				<div class="inquiry-automation__row-words">
					<span class="inquiry-automation__slip-name">{stopping.recipe_name}</span>
					<span class="inquiry-automation__row-line"
						>{sentLine(stopping)}{stopping.next_due_at
							? ` · next ${dateTimeFormat.format(new Date(stopping.next_due_at))}`
							: ''}</span
					>
				</div>
			</div>
		{/if}
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

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Design skill `cards.md` → Automatic follow-up card; Pencil `jXc9n` (Approved B, "Next message first").
	.inquiry-automation {
		display: flex;
		flex-direction: column;
		gap: 14px;

		&__panel {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: 14px;
			border: var(--border-base) solid var(--panel-edge);
			border-radius: 12px;
			background: var(--panel-surface);
		}

		&__top {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__name {
			flex: 1 1 auto;
			min-width: 0;
			overflow: hidden;
			color: var(--panel-on);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__when {
			display: flex;
			flex-direction: column;
			gap: 2px;
		}

		&__kicker {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__big {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			letter-spacing: -0.4px;
			line-height: var(--typography--lineHeight-tight);

			&--reason {
				font-size: var(--typography--fontSize-larger);
			}
		}

		&__under {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}

		&__trail {
			display: flex;
			align-items: center;
			gap: 10px;
		}

		&__steps {
			display: inline-flex;
			align-items: center;
		}

		&__sent,
		&__next {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 20px;
			height: 20px;
			box-sizing: border-box;
			border-radius: var(--radius-circle);
		}

		&__sent {
			color: var(--color-surface);
			background: var(--panel-tone);

			:global(svg) {
				width: 12px;
				height: 12px;
				stroke-width: 3;
			}
		}

		&__next {
			border: 2px solid var(--panel-tone);
			background: var(--color-surface);

			&::after {
				width: 6px;
				height: 6px;
				border-radius: var(--radius-circle);
				background: var(--panel-tone);
				content: '';
			}
		}

		&__link {
			width: 14px;
			height: 2px;
			background: var(--panel-tone);
		}

		&__count {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__strip {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: 7px 10px;
			border: var(--border-base) solid var(--color-warning--surface-edge);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			span {
				display: inline-flex;
				flex: 0 0 auto;
				padding-top: 1px;
			}
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__actions {
			display: flex;
			gap: 6px;

			> :global(.button) {
				flex: 1 1 0;
				min-width: 0;
				padding: 0 10px;
			}
		}

		&__earlier {
			display: flex;
			flex-direction: column;
			gap: 10px;

			&--lined {
				padding-top: var(--space-slim);
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__overline {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: 10px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: 10px;
		}

		&__row-words {
			display: flex;
			flex: 1 1 auto;
			min-width: 0;
			flex-direction: column;
			gap: 1px;
		}

		&__row-name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__row-line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__slip {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			margin-bottom: var(--space-base);
			padding: var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__slip-name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
	}
</style>
