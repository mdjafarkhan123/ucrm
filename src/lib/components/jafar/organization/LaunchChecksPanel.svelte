<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		organizationLaunchChecksQuery,
		organizationLaunchChecksUrl
	} from '$lib/jafar/organization-setup-queries';
	import { jafarOrganizationLaunchChecksKey } from '$lib/jafar/query-keys';
	import {
		LAUNCH_CHECK_HINT,
		LAUNCH_CHECK_REASON_MAX,
		LAUNCH_CHECK_TITLE,
		launchCheckWaitingLabel,
		launchWaitLine,
		uncheckedLaunchLines,
		type LaunchCheckKey,
		type LaunchCheckLine
	} from '$lib/setup/launch-checks';
	import { formatDateTime } from './format';

	// Client onboarding E5 (plan §6): Uplift's checks before asking for launch approval, on the newest released
	// preview. Jafar tests each line and ticks it, or marks it Doesn't apply with a reason. A line that depends on an
	// outside wait still open shows who it waits on and cannot be ticked; it never blocks Ask. A new release starts a
	// fresh list; once Ask is pressed the list is kept with the request and stops changing.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const query = createQuery(() => organizationLaunchChecksQuery(organizationId));

	const checklist = $derived(query.data ?? null);
	const left = $derived(checklist ? uncheckedLaunchLines(checklist).length : 0);
	const locked = $derived(checklist?.asked ?? true);

	let marking = $state<LaunchCheckKey | null>(null);
	let reason = $state('');
	let error = $state('');

	const save = createMutation(() => ({
		mutationFn: async (input: {
			check_key: LaunchCheckKey;
			outcome: 'checked' | 'not_applicable' | null;
			reason?: string;
		}) => {
			const response = await fetch(organizationLaunchChecksUrl(organizationId), {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ version: checklist!.version, ...input })
			});
			const result = (await response.json().catch(() => ({}))) as {
				error?: string;
				field_errors?: Record<string, string>;
			};
			if (!response.ok)
				throw new Error(
					Object.values(result.field_errors ?? {})[0] ??
						result.error ??
						'That could not be saved. Try again.'
				);
		},
		onMutate: () => (error = ''),
		onSuccess: () => {
			marking = null;
			reason = '';
		},
		onError: (cause) => {
			marking = null;
			error = cause.message;
		},
		// Ask for launch approval reads the same list.
		onSettled: () =>
			queryClient.invalidateQueries({ queryKey: jafarOrganizationLaunchChecksKey(organizationId) })
	}));

	const who = (line: LaunchCheckLine) =>
		[line.checked_by_email, line.checked_at ? formatDateTime(line.checked_at) : null]
			.filter(Boolean)
			.join(', ');
</script>

{#if query.isPending}
	<LoadingSkeleton variant="card" label="Loading launch checks" />
{:else if query.isError}
	<ErrorState
		title="Launch checks could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if checklist}
	<SectionBlock
		title="Launch checks"
		icon={listCheckIcon}
		hint="Test each line on preview version {checklist.version} before asking for launch approval. A line waiting on an outside company is named to the approver, never ticked."
	>
		{#snippet actions()}
			{#if checklist.asked}
				<StatusBadge status="inactive">Kept with the request</StatusBadge>
			{:else if left > 0}
				<StatusBadge status="warning">{left} left</StatusBadge>
			{:else}
				<StatusBadge status="success">Ready to ask</StatusBadge>
			{/if}
		{/snippet}

		<div class="launch-checks">
			{#if error}<Banner type="error">{error}</Banner>{/if}
			{#if checklist.asked}
				<p class="launch-checks__muted">
					Launch approval was asked for on version {checklist.version}, so this list is kept as it
					was. Release a new version to check again.
				</p>
			{/if}

			<ul class="launch-checks__list">
				{#each checklist.lines as line (line.key)}
					<li class="launch-checks__row">
						<div class="launch-checks__main">
							<Checkbox
								id="launch-check-{line.key}"
								label={LAUNCH_CHECK_TITLE[line.key]}
								description={LAUNCH_CHECK_HINT[line.key]}
								checked={line.state === 'checked'}
								disabled={locked ||
									save.isPending ||
									line.state === 'waiting' ||
									line.state === 'not_applicable'}
								onchange={(checked) =>
									save.mutate({ check_key: line.key, outcome: checked ? 'checked' : null })}
							/>
							{#if line.state === 'not_applicable' && line.reason}
								<p class="launch-checks__reason">{line.reason}</p>
							{/if}
						</div>
						<div class="launch-checks__side">
							{#if line.state === 'waiting'}
								<StatusBadge status="informative"
									>{launchCheckWaitingLabel(line.waiting_on)}</StatusBadge
								>
							{:else if line.state === 'not_applicable'}
								<StatusBadge status="inactive">Doesn’t apply</StatusBadge>
							{/if}
							{#if (line.state === 'checked' || line.state === 'not_applicable') && who(line)}
								<span class="launch-checks__muted">{who(line)}</span>
							{/if}
							{#if !locked && line.state === 'unchecked'}
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									disabled={save.isPending}
									onclick={() => {
										error = '';
										reason = '';
										marking = line.key;
									}}>Doesn’t apply</Button
								>
							{:else if !locked && line.state === 'not_applicable'}
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									disabled={save.isPending}
									onclick={() => save.mutate({ check_key: line.key, outcome: null })}>Undo</Button
								>
							{/if}
						</div>
					</li>
				{/each}
			</ul>

			{#if checklist.waits.length}
				<div class="launch-checks__waits">
					<strong>Still waiting on others</strong>
					<ul>
						{#each checklist.waits as wait (wait.key)}
							<li>{launchWaitLine(wait)}</li>
						{/each}
					</ul>
				</div>
			{/if}
		</div>
	</SectionBlock>

	<ConfirmDialog
		open={marking !== null}
		title="Mark as doesn’t apply"
		confirmLabel="Mark doesn’t apply"
		loading={save.isPending}
		confirmDisabled={!reason.trim()}
		onConfirm={() =>
			marking &&
			save.mutate({ check_key: marking, outcome: 'not_applicable', reason: reason.trim() })}
		onClose={() => (marking = null)}
	>
		<p>
			{marking ? LAUNCH_CHECK_TITLE[marking] : ''}. The approver sees this line as not applying,
			with your reason.
		</p>
		<Textarea
			id="launch-check-reason"
			label="Why doesn’t it apply?"
			placeholder="For example: they had no clients to import"
			rows={2}
			maxlength={LAUNCH_CHECK_REASON_MAX}
			bind:value={reason}
		/>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.launch-checks {
		display: grid;
		gap: var(--space-base);

		&__list {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
			padding: var(--space-slim) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__main {
			display: grid;
			flex: 1 1 320px;
			gap: var(--space-smaller);
		}

		&__side {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__reason {
			margin: 0 0 0 var(--space-large);
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__waits {
			display: grid;
			gap: var(--space-smaller);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);

			strong {
				color: var(--color-heading);
			}

			ul {
				display: grid;
				gap: var(--space-smallest);
				margin: 0;
				padding-left: var(--space-base);
			}
		}
	}
</style>
