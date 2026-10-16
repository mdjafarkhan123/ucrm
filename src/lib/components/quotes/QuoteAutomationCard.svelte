<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import QuoteAutomationEnrollDialog from './QuoteAutomationEnrollDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchQuoteAutomation,
		controlEnrollment,
		quoteAutomationKey,
		type RecordEnrollment,
		type EnrollmentControl
	} from '$lib/quotes/automation';
	import type { QuoteWriteError } from '$lib/quotes/api';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import playIcon from '@tabler/icons/outline/player-play.svg?raw';
	import skipIcon from '@tabler/icons/outline/player-skip-forward.svg?raw';
	import stopIcon from '@tabler/icons/outline/player-stop.svg?raw';

	// The Quote detail's record-level Automation controls (contractor pilot). Nothing loads with the page:
	// the card shows a skeleton and only fetches its enrollments once the pointer reaches it. When the server
	// says this viewer has no Automation access, the whole card hides itself rather than showing an error.
	let { quoteId }: { quoteId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let warm = $state(false);

	const query = createQuery(() => ({
		queryKey: quoteAutomationKey(quoteId),
		queryFn: () => fetchQuoteAutomation(quoteId),
		enabled: warm && Boolean(quoteId),
		staleTime: 15_000,
		retry: false
	}));

	// A 403 from the access gate (not part of the plan, or no view permission) means this viewer should not
	// see the card at all; a real failure still shows a retry.
	const accessDenied = $derived.by(() => {
		const reason = (query.error as QuoteWriteError | null)?.reason;
		return reason === 'not_included' || reason === 'permission_denied';
	});

	const data = $derived(query.data);
	const enrollments = $derived<RecordEnrollment[]>(data?.enrollments ?? []);
	const canControl = $derived(Boolean(data?.can_control));

	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		hour: 'numeric',
		minute: '2-digit'
	});

	const STATE_TONE: Record<
		string,
		'success' | 'warning' | 'critical' | 'inactive' | 'informative'
	> = {
		active: 'informative',
		paused: 'warning',
		completed: 'success',
		stopped: 'inactive',
		failed: 'critical'
	};

	function stateTone(state: string) {
		return STATE_TONE[state] ?? 'inactive';
	}

	function stateLabel(state: string) {
		return state.charAt(0).toUpperCase() + state.slice(1);
	}

	// The engine writes its own stop reasons as internal codes; a staff member's typed reason is free text.
	// Translate the codes and show anything else as written, so nobody reads `quote_not_awaiting_response`.
	const ENGINE_STOP_REASON: Record<string, string> = {
		quote_not_awaiting_response: 'Stopped because the quote is no longer awaiting a response',
		quote_not_sendable: 'Stopped because the quote is no longer available',
		follow_ups_declined: 'Stopped because this client turned quote follow-ups off',
		recipient_unavailable: 'Stopped because there is no email address to send to',
		recipe_not_active: 'Stopped because the automation was turned off',
		enrollment_expired: 'Stopped because it reached the maximum follow-up length',
		automations_not_entitled: 'Stopped because automations are not included in the current plan',
		automation_suspended: 'Stopped because automations are paused for this account',
		invalid_email_content: 'Stopped because the follow-up email has no message',
		invalid_link: 'Stopped because the customer link could not be created',
		idempotency_conflict: 'Stopped because a conflicting send was already recorded'
	};

	function stopReasonLine(reason: string): string {
		return ENGINE_STOP_REASON[reason] ?? reason;
	}

	function nextLine(enrollment: RecordEnrollment): string {
		if (enrollment.state === 'active' && enrollment.next_due_at)
			return `Next step ${dateTimeFormat.format(new Date(enrollment.next_due_at))}`;
		if (enrollment.state === 'paused') return 'Paused — resume to continue';
		const sent = enrollment.customer_messages_sent;
		return `${sent} customer message${sent === 1 ? '' : 's'} sent`;
	}

	let enrolling = $state(false);
	let pendingId = $state<string | null>(null);
	let stoppingId = $state<string | null>(null);
	let stopReason = $state('');

	async function invalidate() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: quoteAutomationKey(quoteId) }),
			queryClient.invalidateQueries({ queryKey: ['settings', 'automation'] })
		]);
	}

	async function runControl(enrollmentId: string, control: EnrollmentControl, done: string) {
		if (pendingId) return;
		pendingId = enrollmentId;
		try {
			await controlEnrollment(quoteId, enrollmentId, control);
			await invalidate();
			toast.success(done);
		} catch (error) {
			toast.error((error as QuoteWriteError).message || 'That change could not be applied.');
		} finally {
			pendingId = null;
		}
	}

	function menuItems(enrollment: RecordEnrollment) {
		const disabled = pendingId !== null;
		const items = [];
		if (enrollment.state === 'active')
			items.push({
				label: 'Pause',
				icon: pauseIcon,
				disabled,
				onSelect: () =>
					void runControl(enrollment.enrollment_id, { action: 'pause' }, 'Automation paused')
			});
		if (enrollment.state === 'paused')
			items.push({
				label: 'Resume',
				icon: playIcon,
				disabled,
				onSelect: () =>
					void runControl(enrollment.enrollment_id, { action: 'resume' }, 'Automation resumed')
			});
		items.push({
			label: 'Skip next step',
			icon: skipIcon,
			disabled,
			onSelect: () =>
				void runControl(enrollment.enrollment_id, { action: 'skip' }, 'Next step skipped')
		});
		items.push({
			label: 'Stop',
			icon: stopIcon,
			destructive: true,
			disabled,
			onSelect: () => {
				stopReason = '';
				stoppingId = enrollment.enrollment_id;
			}
		});
		return items;
	}

	// Only a running enrollment (active or paused) has controls; a finished one is history only.
	function isRunning(enrollment: RecordEnrollment) {
		return enrollment.state === 'active' || enrollment.state === 'paused';
	}

	async function confirmStop() {
		if (!stoppingId) return;
		const id = stoppingId;
		const reason = stopReason.trim();
		await runControl(id, { action: 'stop', reason: reason || undefined }, 'Automation stopped');
		stoppingId = null;
	}
</script>

{#if !accessDenied}
	<div role="presentation" onmouseenter={() => (warm = true)} onfocusin={() => (warm = true)}>
		<RailCard title="Automation" description="Follow-ups sent for you" icon={robotIcon} flush>
			{#snippet actions()}
				{#if canControl && (data?.enrollable_recipes.length ?? 0) > 0}
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						class="quote-automation__enrol"
						onclick={() => (enrolling = true)}
					>
						<span class="quote-automation__plus" aria-hidden="true">{@html plusIcon}</span>
						Enrol
					</Button>
				{/if}
			{/snippet}

			{#if !warm || query.isPending}
				<div class="quote-automation__pad">
					<LoadingSkeleton variant="table" rows={2} label="Loading automations" />
				</div>
			{:else if query.isError}
				<div class="quote-automation__pad">
					<ErrorState
						description="Automation history could not be loaded."
						retry={() => query.refetch()}
					/>
				</div>
			{:else if enrollments.length === 0}
				<div class="quote-automation__pad">
					<EmptyState
						icon={robotIcon}
						title="No automations"
						description="This quote isn't in any follow-up automation yet."
					/>
				</div>
			{:else}
				<ul class="quote-automation__list">
					{#each enrollments as enrollment (enrollment.enrollment_id)}
						<li class="quote-automation__row">
							<span class="quote-automation__icon" aria-hidden="true">{@html robotIcon}</span>
							<div class="quote-automation__body">
								<div class="quote-automation__heading">
									<span class="quote-automation__name">{enrollment.recipe_name}</span>
									<span class="quote-automation__version">v{enrollment.version_number}</span>
								</div>
								<div class="quote-automation__status">
									<StatusBadge status={stateTone(enrollment.state)}>
										{stateLabel(enrollment.state)}
									</StatusBadge>
									<p class="quote-automation__meta">{nextLine(enrollment)}</p>
								</div>
								{#if enrollment.state === 'stopped' && enrollment.stop_reason}
									<p class="quote-automation__reason">{stopReasonLine(enrollment.stop_reason)}</p>
								{/if}
							</div>
							{#if canControl && isRunning(enrollment)}
								<DropdownMenu
									items={menuItems(enrollment)}
									triggerLabel="Automation actions"
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

{#if enrolling}
	<QuoteAutomationEnrollDialog
		{quoteId}
		recipes={data?.enrollable_recipes ?? []}
		onClose={() => (enrolling = false)}
		onEnrolled={async () => {
			enrolling = false;
			await invalidate();
			toast.success('Quote enrolled');
		}}
	/>
{/if}

{#if stoppingId}
	<ConfirmDialog
		open
		title="Stop this automation?"
		tone="critical"
		confirmLabel="Stop automation"
		destructive
		loading={pendingId !== null}
		onConfirm={confirmStop}
		onClose={() => (stoppingId = null)}
	>
		<p>
			No more steps will run for this quote. Messages already sent are not recalled. You can say why
			below.
		</p>
		<Textarea
			id="stop-reason"
			label="Reason (optional)"
			rows={3}
			maxlength={200}
			bind:value={stopReason}
		/>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.quote-automation__pad {
		padding: 0 20px 18px;
	}

	:global(.quote-automation__enrol) {
		border-color: var(--color-border--interactive);
		border-radius: 10px;
		color: var(--color-heading);
		font-size: 13px;
		font-weight: 600;
	}

	.quote-automation__plus {
		display: inline-flex;
		margin-right: 6px;
		color: var(--color-text--secondary);
	}

	.quote-automation__plus :global(svg) {
		display: block;
		width: 14px;
		height: 14px;
	}

	.quote-automation__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.quote-automation__row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 14px 20px 18px;
		border-top: var(--border-base) solid var(--color-border);
	}

	.quote-automation__icon {
		display: inline-grid;
		flex: 0 0 auto;
		width: 32px;
		height: 32px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	.quote-automation__body {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.quote-automation__status {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 4px 8px;
	}

	.quote-automation__heading {
		display: flex;
		align-items: baseline;
		gap: 6px;
	}

	.quote-automation__name {
		color: var(--color-heading);
		font-size: 13px;
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.quote-automation__version {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.quote-automation__meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.quote-automation__reason {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-style: italic;
	}
</style>
