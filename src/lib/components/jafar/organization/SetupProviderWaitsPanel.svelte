<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ProviderWaitDialog from './ProviderWaitDialog.svelte';
	import {
		organizationProviderWaitsQuery,
		organizationProviderWaitsUrl
	} from '$lib/jafar/organization-setup-queries';
	import { jafarOnboardingKey, jafarOrganizationKey } from '$lib/jafar/query-keys';
	import {
		PROVIDER_WAITS,
		PROVIDER_WAIT_TITLE,
		providerWaitOwnerLabel,
		providerWaitTone,
		type ProviderWaitKey,
		type ProviderWaitStatus
	} from '$lib/setup/provider-waits';
	import { formatDateTime } from './format';

	// Client onboarding E2 (plan §5): the outside waits this client's package offers — Google, the carriers, a
	// number transfer, their domain — and where each stands. Jafar moves them by hand; the client sees a wait once
	// it is started, and "They need to do something" emails them. Waits never move Uplift's dates or block Ready.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const query = createQuery(() => organizationProviderWaitsQuery(organizationId));

	let editing = $state<ProviderWaitKey | null>(null);
	let saveError = $state('');
	let notice = $state('');

	const save = createMutation(() => ({
		mutationFn: async (input: {
			wait_key: ProviderWaitKey;
			status: ProviderWaitStatus | null;
			note: string | null;
		}) => {
			const response = await fetch(organizationProviderWaitsUrl(organizationId), {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json().catch(() => ({}))) as {
				emailed?: boolean;
				error?: string;
				field_errors?: Record<string, string>;
			};
			if (!response.ok)
				throw new Error(
					Object.values(result.field_errors ?? {})[0] ??
						result.error ??
						'That could not be saved. Try again.'
				);
			return { emailed: result.emailed !== false, status: input.status };
		},
		onMutate: () => {
			saveError = '';
			notice = '';
		},
		onSuccess: (result) => {
			editing = null;
			if (result.status === 'action_needed' && !result.emailed)
				notice =
					'Saved, but the email to the client could not be queued. Press Save on it again to retry.';
		},
		onError: (error) => {
			saveError = error.message;
		},
		// This panel, the Onboarding list and the Activity tab's history all change.
		onSettled: () =>
			Promise.all([
				queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) }),
				queryClient.invalidateQueries({ queryKey: jafarOnboardingKey })
			])
	}));

	// The package's waits, and any started before the package dropped its service, so Jafar can still clear it.
	const shown = $derived(
		PROVIDER_WAITS.filter(
			(key) =>
				query.data?.offered.includes(key) || query.data?.waits.some((wait) => wait.key === key)
		)
	);
	const waitFor = (key: ProviderWaitKey) =>
		query.data?.waits.find((wait) => wait.key === key) ?? null;
	const openCount = $derived(
		(query.data?.waits ?? []).filter(
			(wait) => wait.status !== 'approved' && wait.status !== 'unavailable'
		).length
	);
</script>

{#if query.isPending}
	<LoadingSkeleton variant="card" label="Loading outside waits" />
{:else if query.isError}
	<ErrorState
		title="Outside waits could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if shown.length > 0}
	<SectionBlock
		title="Outside waits"
		icon={hourglassIcon}
		hint="Steps Google, the phone carriers or the client's domain company take. The client sees a wait once you start it; none of them moves Uplift's dates or blocks Ready."
	>
		{#snippet actions()}
			{#if openCount > 0}
				<StatusBadge status="informative">{openCount} open</StatusBadge>
			{/if}
		{/snippet}
		<ul class="provider-waits">
			{#each shown as key (key)}
				{@const wait = waitFor(key)}
				<li class="provider-waits__row">
					<div class="provider-waits__main">
						<strong>{PROVIDER_WAIT_TITLE[key]}</strong>
						{#if wait}
							<span class="provider-waits__muted">Updated {formatDateTime(wait.updated_at)}</span>
							{#if wait.note}<p class="provider-waits__note">{wait.note}</p>{/if}
						{:else}
							<span class="provider-waits__muted">Not started — the client does not see it</span>
						{/if}
						{#if wait && !query.data.offered.includes(key)}
							<span class="provider-waits__muted"
								>Their package no longer includes this service — clear it when it is finished.</span
							>
						{/if}
					</div>
					<div class="provider-waits__side">
						{#if wait}
							<StatusBadge status={providerWaitTone(wait.status)}
								>{providerWaitOwnerLabel(key, wait.status)}</StatusBadge
							>
						{/if}
						<Button
							size="small"
							variant="secondary"
							variation="subtle"
							onclick={() => {
								saveError = '';
								editing = key;
							}}>{wait ? 'Change' : 'Start'}</Button
						>
					</div>
				</li>
			{/each}
		</ul>
		{#if notice}
			<p class="provider-waits__notice" role="status">{notice}</p>
		{/if}
	</SectionBlock>
{/if}

{#if editing}
	<ProviderWaitDialog
		waitKey={editing}
		current={waitFor(editing)}
		pending={save.isPending}
		error={saveError}
		onSubmit={(input) => editing && save.mutate({ wait_key: editing, ...input })}
		onClose={() => (editing = null)}
	/>
{/if}

<style lang="scss">
	.provider-waits {
		display: grid;
		margin: 0;
		padding: 0;
		list-style: none;

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
			flex: 1 1 260px;
			gap: var(--space-smallest);

			strong {
				color: var(--color-heading);
			}
		}

		&__side {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text);
			white-space: pre-line;
		}

		&__notice {
			margin: var(--space-small) 0 0;
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
