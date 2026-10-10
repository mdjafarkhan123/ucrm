<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import arrowsExchangeIcon from '@tabler/icons/outline/arrows-exchange.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		organizationMigrationComparisonQuery,
		organizationMigrationQuery
	} from '$lib/jafar/organization-experience-queries';
	import { jafarOrganizationKey, jafarOrganizationMigrationKey } from '$lib/jafar/query-keys';
	import { canUseJafarPath } from '$lib/jafar/team-access';
	import { isStoppingChange, type MigrationTabResponse } from '$lib/experience/migration';
	import { formatDateTime } from './format';

	// Multi-industry foundation B10: before a business is moved onto its confirmed Industry experience,
	// Uplift takes an inventory of everything it has and what customers can still reach, takes another after,
	// and compares them. If anything differs unexpectedly the business can be switched back to its previous
	// Contractor access; the profile, history and every record stay exactly as they are. It loads when
	// Uplift asks for it, not with the tab.
	let { organizationId, hasProfile }: { organizationId: string; hasProfile: boolean } = $props();

	const queryClient = useQueryClient();
	let requested = $state(false);
	const overview = createQuery(() => ({
		...organizationMigrationQuery(organizationId),
		enabled: requested
	}));
	const data = $derived(overview.data);
	const canChange = $derived(
		canUseJafarPath(
			{ role: page.data.owner.role, access: page.data.owner.access },
			`/api/jafar/organizations/${organizationId}/migration`,
			'POST'
		)
	);

	let from = $state('');
	let to = $state('');
	const compared = createQuery(() => ({
		...organizationMigrationComparisonQuery(organizationId, from, to),
		enabled: requested && Boolean(from) && Boolean(to) && from !== to
	}));
	const comparison = $derived(compared.data?.comparison);

	// Newest snapshot is "after", the one before it "before", until Uplift chooses otherwise.
	let chosen = $state(false);
	$effect(() => {
		if (chosen || !data || data.snapshots.length < 2) return;
		to = data.snapshots[0].id;
		from = data.snapshots[1].id;
	});
	const snapshotOptions = $derived(
		(data?.snapshots ?? []).map((snapshot) => ({
			value: snapshot.id,
			label: `${snapshot.label} · ${formatDateTime(snapshot.taken_at)}`
		}))
	);

	let label = $state('');
	let actionError = $state('');
	let pathDialog = $state(false);
	let pathReason = $state('');
	let pathKey = $state('');
	const targetPath = $derived(
		data?.path === 'previous_contractor' ? 'experience' : 'previous_contractor'
	);

	async function send(body: unknown): Promise<MigrationTabResponse> {
		const response = await fetch(`/api/jafar/organizations/${organizationId}/migration`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
		const result = (await response.json()) as MigrationTabResponse & {
			field_errors?: Record<string, string>;
		};
		if (!response.ok)
			throw new Error(
				Object.values(result.field_errors ?? {})[0] ??
					result.error ??
					'That did not work. Try again.'
			);
		return result;
	}

	const snapshot = createMutation(() => ({
		mutationFn: () => send({ action: 'snapshot', label }),
		onSuccess: (result) => {
			queryClient.setQueryData(jafarOrganizationMigrationKey(organizationId), result);
			label = '';
			actionError = '';
			chosen = false;
		},
		onError: (error) => (actionError = error.message)
	}));

	const switchPath = createMutation(() => ({
		mutationFn: () =>
			send({ action: 'path', path: targetPath, reason: pathReason, idempotency_key: pathKey }),
		onSuccess: (result) => {
			queryClient.setQueryData(jafarOrganizationMigrationKey(organizationId), result);
			// Who can do what just changed, so every answer built from it is read again.
			void queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) });
			pathDialog = false;
			pathReason = '';
			actionError = '';
		},
		onError: (error) => (actionError = error.message)
	}));

	function openPathDialog() {
		pathKey = crypto.randomUUID();
		actionError = '';
		pathDialog = true;
	}

	const KIND_LABELS = {
		lost: 'Missing',
		replaced: 'Different records',
		added: 'New work',
		edited: 'Edited'
	} as const;

	const tableName = (name: string) => name.replace(/^(public|private)\./, '').replaceAll('_', ' ');
</script>

<SectionBlock
	title="Migration check"
	icon={arrowsExchangeIcon}
	hint="Take an inventory before and after moving a business, compare them, and switch back if anything is missing. Nothing here deletes a record."
>
	<div class="migration">
		{#if !requested}
			<div class="migration__row">
				<Button
					variant="secondary"
					size="small"
					onhover={() => void queryClient.prefetchQuery(organizationMigrationQuery(organizationId))}
					onclick={() => (requested = true)}>Open migration check</Button
				>
			</div>
		{:else if overview.isPending}
			<LoadingSkeleton variant="card" label="Loading migration check" />
		{:else if overview.isError && !data}
			<ErrorState
				title="The migration check could not be loaded"
				description={overview.error.message}
				retry={() => overview.refetch()}
			/>
		{:else if data}
			<div class="migration__row">
				<div class="migration__path">
					{#if data.path === 'previous_contractor'}
						<Badge status="warning">Previous access</Badge>
						<span class="migration__muted"
							>Access ignores the confirmed profile and follows the package’s Contractor audience.</span
						>
					{:else}
						<Badge status="success">{hasProfile ? 'Confirmed profile' : 'Package audience'}</Badge>
						<span class="migration__muted"
							>{hasProfile
								? 'Access follows the confirmed profile.'
								: 'No profile is confirmed yet, so access follows the package’s audience, as before.'}</span
						>
					{/if}
				</div>
				{#if canChange}
					<Button variant="secondary" variation="subtle" size="small" onclick={openPathDialog}>
						{data.path === 'previous_contractor'
							? 'Return to the profile'
							: 'Switch back to previous access'}
					</Button>
				{/if}
			</div>

			{#if canChange}
				<form
					class="migration__take"
					onsubmit={(event) => {
						event.preventDefault();
						if (!label.trim()) {
							actionError = 'Name this snapshot, for example “Before cutover”.';
							return;
						}
						snapshot.mutate();
					}}
				>
					<Input id="migration-label" label="Snapshot name" maxlength={80} bind:value={label} />
					<Button type="submit" size="small" loading={snapshot.isPending}>Take snapshot</Button>
				</form>
				{#if actionError && !pathDialog}
					<p class="migration__error" role="alert">{actionError}</p>
				{/if}
			{/if}

			{#if data.snapshots.length === 0}
				<p class="migration__muted">No snapshots yet. Take one before changing anything.</p>
			{:else}
				<ul class="migration__snapshots">
					{#each data.snapshots as item (item.id)}
						<li>
							<strong>{item.label}</strong>
							<span class="migration__muted"
								>{formatDateTime(item.taken_at)} · {item.rows.toLocaleString()} records in {item.tables}
								areas · {item.actor_email}</span
							>
						</li>
					{/each}
				</ul>
			{/if}

			{#if data.snapshots.length >= 2}
				<div class="migration__compare">
					<Select
						id="migration-from"
						label="Before"
						options={snapshotOptions}
						value={from}
						onchange={(value) => {
							from = value;
							chosen = true;
						}}
					/>
					<Select
						id="migration-to"
						label="After"
						options={snapshotOptions}
						value={to}
						onchange={(value) => {
							to = value;
							chosen = true;
						}}
					/>
				</div>
				{#if from === to}
					<p class="migration__muted">Choose two different snapshots to compare.</p>
				{:else if compared.isPending}
					<LoadingSkeleton variant="card" label="Comparing snapshots" />
				{:else if compared.isError}
					<ErrorState
						title="The snapshots could not be compared"
						description={compared.error.message}
						retry={() => compared.refetch()}
					/>
				{:else if comparison}
					{@const result = comparison.result}
					{#if result.verdict === 'same'}
						<Banner type="success">
							<strong>Nothing differs.</strong> All {result.rows_after.toLocaleString()} records in {result.tables_compared}
							areas, the agreement, the team and every customer link match.
						</Banner>
					{:else if result.verdict === 'changed'}
						<Banner type="notice">
							<strong>Only ordinary work or the access path changed.</strong> Nothing is missing or replaced.
						</Banner>
					{:else}
						<Banner type="error">
							<strong>Stop and look.</strong> Something the business had is missing or different. Do not
							move the next business until it is explained.
						</Banner>
					{/if}

					{#if result.facts.length}
						<h3 class="migration__heading">Business facts</h3>
						<ul class="migration__changes">
							{#each result.facts as fact (fact.fact)}
								<li>
									<Badge status={fact.stops ? 'critical' : 'informative'}
										>{fact.stops ? 'Stop' : 'Note'}</Badge
									>
									<span><strong>{fact.fact}:</strong> {fact.before} → {fact.after}</span>
								</li>
							{/each}
						</ul>
					{/if}
					{#if result.records.length}
						<h3 class="migration__heading">Records</h3>
						<ul class="migration__changes">
							{#each result.records as change (change.table)}
								<li>
									<Badge status={isStoppingChange(change.kind) ? 'critical' : 'informative'}
										>{KIND_LABELS[change.kind]}</Badge
									>
									<span
										><strong>{tableName(change.table)}:</strong>
										{change.before} → {change.after}</span
									>
								</li>
							{/each}
						</ul>
					{/if}
				{/if}
			{/if}

			{#if data.path_history.length}
				<h3 class="migration__heading">Path history</h3>
				<ul class="migration__changes">
					{#each data.path_history as change (change.id)}
						<li>
							<Badge status="informative"
								>{change.path === 'previous_contractor'
									? 'Switched back'
									: 'Returned to profile'}</Badge
							>
							<span
								>{formatDateTime(change.changed_at)} · {change.actor_email} · {change.reason}</span
							>
						</li>
					{/each}
				</ul>
			{/if}
		{/if}
	</div>
</SectionBlock>

{#if pathDialog}
	<Dialog
		open
		title={targetPath === 'previous_contractor'
			? 'Switch back to previous access'
			: 'Return to the profile'}
		initialFocusId="migration-path-reason"
		onClose={() => (pathDialog = false)}
	>
		<form
			class="migration__dialog"
			onsubmit={(event) => {
				event.preventDefault();
				if (!pathReason.trim()) {
					actionError = 'Explain why you are switching.';
					return;
				}
				switchPath.mutate();
			}}
			novalidate
		>
			<p class="migration__muted">
				{targetPath === 'previous_contractor'
					? 'The business’s access is judged by its package alone, as it was before profiles. The profile, its history, the agreement and every record stay as they are.'
					: 'The business’s access follows its confirmed profile again.'}
			</p>
			<Textarea
				id="migration-path-reason"
				label="Why are you switching?"
				rows={3}
				maxlength={1000}
				required
				bind:value={pathReason}
			/>
			{#if actionError}
				<p class="migration__error" role="alert">{actionError}</p>
			{/if}
			<div class="migration__dialog-actions">
				<Button
					type="button"
					variant="secondary"
					variation="subtle"
					onclick={() => (pathDialog = false)}>Cancel</Button
				>
				<Button type="submit" loading={switchPath.isPending}>Switch</Button>
			</div>
		</form>
	</Dialog>
{/if}

<style lang="scss">
	.migration {
		display: grid;
		gap: var(--space-base);
		min-width: 0;

		&__row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__path {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
		}

		&__take {
			display: grid;
			grid-template-columns: minmax(0, 1fr) auto;
			align-items: end;
			gap: var(--space-small);
		}

		&__compare {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__heading {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
		}

		&__snapshots,
		&__changes {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__snapshots li {
			display: grid;
			gap: var(--space-smallest);
		}

		&__changes li {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-small);
			overflow-wrap: anywhere;
		}

		&__dialog {
			display: grid;
			gap: var(--space-base);
		}

		&__dialog-actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 639px) {
		.migration__take,
		.migration__compare {
			grid-template-columns: 1fr;
		}
	}
</style>
