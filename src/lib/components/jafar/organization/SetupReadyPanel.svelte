<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import { organizationSetupReadyUrl } from '$lib/jafar/organization-setup-queries';
	import { jafarOnboardingKey, jafarOrganizationKey } from '$lib/jafar/query-keys';
	import type { ClientSetupView } from '$lib/setup/client-page';
	import {
		SETUP_READY_DAYS,
		SETUP_READY_REASON_MAX,
		formatReadyDate,
		previewSetupReadyRange,
		setupReadyBlockerText,
		type SetupReadyBlocker
	} from '$lib/setup/ready';
	import { formatDateTime } from './format';

	// Client onboarding C4 (plan §4–5, §10 journey 7): Ready for Uplift starts the client's 7–10 business-day
	// build. Every blocker is named, and the button stays off until none is left (Jafar, 2026-10-05). A
	// confirmation shows the dates the client will see before it is recorded; a mistaken Ready is taken back with
	// a reason, kept in the Activity tab's history.
	let { organizationId, view }: { organizationId: string; view: ClientSetupView } = $props();

	const queryClient = useQueryClient();
	const ready = $derived(view.ready);
	const blockers = $derived(view.ready_blockers ?? []);
	const newest = $derived(view.sends[0]?.number ?? null);

	let confirming = $state(false);
	let withdrawing = $state(false);
	let reason = $state('');
	let reasonError = $state('');
	let actionError = $state('');
	/** Blockers the server found that this page had not shown yet. */
	let serverBlockers = $state<SetupReadyBlocker[]>([]);

	const preview = $derived(previewSetupReadyRange(view.time_zone));

	async function send(method: 'POST' | 'DELETE', body: unknown) {
		const response = await fetch(organizationSetupReadyUrl(organizationId), {
			method,
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
		if (response.ok) return;
		const result = (await response.json().catch(() => ({}))) as {
			error?: string;
			field_errors?: Record<string, string>;
			blockers?: SetupReadyBlocker[];
		};
		serverBlockers = result.blockers ?? [];
		throw new Error(
			Object.values(result.field_errors ?? {})[0] ??
				result.error ??
				'That could not be saved. Try again.'
		);
	}

	const refresh = () =>
		// The Setup tab, the Onboarding list and the Activity tab's history all change.
		Promise.all([
			queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) }),
			queryClient.invalidateQueries({ queryKey: jafarOnboardingKey })
		]);

	const markReady = createMutation(() => ({
		mutationFn: () => send('POST', { send: newest }),
		onMutate: () => {
			actionError = '';
			serverBlockers = [];
		},
		onSuccess: () => {
			confirming = false;
		},
		onError: (error) => {
			confirming = false;
			actionError = error.message;
		},
		onSettled: refresh
	}));

	const withdraw = createMutation(() => ({
		mutationFn: () => send('DELETE', { reason: reason.trim() }),
		onMutate: () => {
			actionError = '';
		},
		onSuccess: () => {
			withdrawing = false;
			reason = '';
		},
		onError: (error) => {
			reasonError = error.message;
		},
		onSettled: refresh
	}));

	function confirmWithdraw() {
		if (!reason.trim()) {
			reasonError = 'Say why you are taking it back.';
			return;
		}
		reasonError = '';
		withdraw.mutate();
	}

	const shownBlockers = $derived(serverBlockers.length > 0 ? serverBlockers : blockers);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="Ready for Uplift"
	icon={rocketIcon}
	hint={`Starts the client’s ${SETUP_READY_DAYS.from}–${SETUP_READY_DAYS.to} business-day build (Monday to Friday). Needs every task accepted and every required help question answered.`}
>
	{#snippet actions()}
		{#if ready}
			<Badge status="success" size="small">Ready — Uplift is building</Badge>
		{:else if shownBlockers.length > 0}
			<Badge status="warning" size="small"
				>{shownBlockers.length} {shownBlockers.length === 1 ? 'blocker' : 'blockers'}</Badge
			>
		{:else}
			<Badge status="informative" size="small">Nothing blocking</Badge>
		{/if}
	{/snippet}

	{#if ready}
		<dl class="setup-ready__facts">
			<div>
				<dt>Started</dt>
				<dd>
					{formatReadyDate(ready.start_date, true)}
					<span class="setup-ready__muted"
						>by {ready.ready_by_email}, {formatDateTime(ready.ready_at)}</span
					>
				</dd>
			</div>
			<div>
				<dt>Ready for their review</dt>
				<dd>
					Between {formatReadyDate(ready.target_from)} and {formatReadyDate(ready.target_to, true)}
					<span class="setup-ready__muted"
						>The client sees these dates · counted in {ready.time_zone} · send {ready.submission_number}</span
					>
				</dd>
			</div>
		</dl>
		{#if newest !== null && newest > ready.submission_number}
			<p class="setup-ready__muted">
				The client has sent changes since you recorded Ready. Review them below; the dates stay as
				they are.
			</p>
		{/if}
		<div class="setup-ready__actions">
			<Button
				size="small"
				variant="tertiary"
				onclick={() => {
					reasonError = '';
					withdrawing = true;
				}}>Take back Ready</Button
			>
		</div>
	{:else}
		{#if shownBlockers.length > 0}
			<ul class="setup-ready__blockers">
				{#each shownBlockers as blocker, index (index)}
					<li>
						<span class="setup-ready__blocker-icon" aria-hidden="true">{@html alertIcon}</span>
						{setupReadyBlockerText(blocker)}
					</li>
				{/each}
			</ul>
		{:else}
			<p>
				Every task is accepted and every required help question is answered. If you record Ready
				now, the client sees their system will be ready for review between
				<strong>{formatReadyDate(preview.target_from)}</strong> and
				<strong>{formatReadyDate(preview.target_to, true)}</strong>.
			</p>
		{/if}
		<div class="setup-ready__actions">
			<Button
				size="small"
				disabled={shownBlockers.length > 0 || newest === null}
				onclick={() => {
					actionError = '';
					confirming = true;
				}}>Ready for Uplift</Button
			>
		</div>
	{/if}
	{#if actionError}
		<p class="setup-ready__error" role="alert">{actionError}</p>
	{/if}
</SectionBlock>

<ConfirmDialog
	open={confirming}
	title="Record Ready for Uplift?"
	icon={rocketIcon}
	tone="success"
	confirmLabel="Record Ready"
	loading={markReady.isPending}
	onConfirm={() => markReady.mutate()}
	onClose={() => (confirming = false)}
>
	<div class="setup-ready__dialog">
		<p>
			The build starts today, {formatReadyDate(preview.start_date)}. The client is shown that their
			system will be ready for their review between
			<strong>{formatReadyDate(preview.target_from)}</strong> and
			<strong>{formatReadyDate(preview.target_to, true)}</strong>.
		</p>
		<p class="setup-ready__muted">
			Counted Monday to Friday in {view.time_zone}. Their setup reminders stay off.
		</p>
	</div>
</ConfirmDialog>

<ConfirmDialog
	open={withdrawing}
	title="Take back Ready for Uplift?"
	tone="critical"
	confirmLabel="Take it back"
	destructive
	loading={withdraw.isPending}
	onConfirm={confirmWithdraw}
	onClose={() => (withdrawing = false)}
>
	<div class="setup-ready__dialog">
		<p>
			The client’s dates disappear. Recording Ready again later starts a fresh
			{SETUP_READY_DAYS.from}–{SETUP_READY_DAYS.to} business days.
		</p>
		<Textarea
			id="setup-ready-withdraw-reason"
			label="Why are you taking it back?"
			rows={3}
			maxlength={SETUP_READY_REASON_MAX}
			required
			bind:value={reason}
			invalid={Boolean(reasonError)}
			errorMessage={reasonError}
		/>
	</div>
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-ready {
		&__muted {
			display: block;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}

		// The confirmations' paragraphs, which ConfirmDialog renders inside this component.
		&__dialog {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__error {
			margin-top: var(--space-small);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__facts {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base) var(--space-large);
			margin: 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				margin: var(--space-smallest) 0 0;
				color: var(--color-heading);
				font-weight: 600;
			}

			@media (max-width: 640px) {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		&__blockers {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: flex-start;
				gap: var(--space-small);
				line-height: var(--typography--lineHeight-base);
			}
		}

		&__blocker-icon {
			display: grid;
			flex: 0 0 18px;
			width: 18px;
			height: 18px;
			margin-top: 2px;
			color: var(--color-warning);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin-top: var(--space-base);
		}
	}
</style>
