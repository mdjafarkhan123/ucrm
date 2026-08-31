<script lang="ts">
	import { createQuery, createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { goto, replaceState } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import SummaryRail from '$lib/components/settings/automation/SummaryRail.svelte';
	import ActivationImpactDialog from '$lib/components/settings/automation/ActivationImpactDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { automationSettingsKey, fetchAutomationSettings } from '$lib/settings/automation';
	import { triggerLabel } from '$lib/automation/catalog';
	import {
		automationRecipeDetailKey,
		automationRecipeVersionsKey,
		automationRecipeHistoryKey,
		automationActivationPreviewKey,
		fetchRecipeDetail,
		fetchRecipeVersions,
		fetchRecipeHistory,
		setRecipeLifecycle,
		duplicateRecipe,
		StaleDraftError,
		type RecipeDetail,
		type RecipeVersion,
		type RecipeHistoryEntry,
		type RecipeHistoryOutcome,
		type LifecycleAction,
		type ActivateResult
	} from '$lib/settings/automation-lifecycle';
	import type { RecipeStatus } from '$lib/settings/automation-recipes';
	import robotOffIcon from '@tabler/icons/outline/robot-off.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import playerPauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';

	let { recipeId }: { recipeId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const accessQuery = createQuery(() => ({
		queryKey: automationSettingsKey,
		queryFn: fetchAutomationSettings
	}));

	const canView = $derived(accessQuery.data?.status === 'ok');

	const detailQuery = createQuery(() => ({
		queryKey: automationRecipeDetailKey(recipeId),
		queryFn: () => fetchRecipeDetail(recipeId),
		enabled: canView
	}));

	// The Versions tab query stays off until the tab is hovered/opened (CLAUDE.md rule 9). Once requested it
	// stays on, so re-opening the tab is instant.
	let versionsRequested = $state(false);
	const versionsQuery = createQuery(() => ({
		queryKey: automationRecipeVersionsKey(recipeId),
		queryFn: () => fetchRecipeVersions(recipeId),
		enabled: canView && versionsRequested
	}));

	// The History tab is the same reveal-on-hover story as Versions, but paginated: a recipe accumulates one
	// row per (event, decision) over its life, so it is a cursor-paginated infinite query, not a bounded read.
	let historyRequested = $state(false);
	const historyQuery = createInfiniteQuery(() => ({
		queryKey: automationRecipeHistoryKey(recipeId),
		queryFn: ({ pageParam }) => fetchRecipeHistory(recipeId, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (last) => last.next_cursor ?? undefined,
		enabled: canView && historyRequested
	}));
	const historyEntries = $derived(historyQuery.data?.pages.flatMap((p) => p.entries) ?? []);

	// URL owns the open tab so a refresh or shared link lands on the same one.
	const activeTab = $derived(page.url.searchParams.get('tab') ?? 'overview');
	function selectTab(next: string) {
		if (next === 'versions') versionsRequested = true;
		if (next === 'history') historyRequested = true;
		const url = new URL(page.url);
		if (next === 'overview') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		// Replaced, not pushed, so Back leaves the automation instead of stepping through tabs. The argument is
		// this same page's URL with one query param changed, not a route id, so resolve() does not apply.
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		replaceState(url, page.state);
	}
	const tabs = $derived([
		{ value: 'overview', label: 'Overview' },
		{ value: 'history', label: 'History', onhover: () => (historyRequested = true) },
		{ value: 'versions', label: 'Versions', onhover: () => (versionsRequested = true) }
	]);

	// Plain-English headline for each match outcome. `detail` (when present) carries the specific reason under
	// it, so these stay short.
	const outcomeLabel: Record<RecipeHistoryOutcome, string> = {
		enrolled: 'Started following up',
		already_enrolled: 'Already being followed up',
		before_activation: 'Happened before this was turned on',
		not_entitled: 'Skipped — not included in the plan',
		authority_blocked: 'Skipped — automation was off',
		subject_gone: 'Skipped — the quote was gone',
		condition_failed: 'Skipped — conditions weren’t met',
		condition_unavailable: 'Couldn’t check the conditions'
	};
	const enrollmentStateLabel: Record<
		NonNullable<RecipeHistoryEntry['enrollment_state']>,
		string
	> = {
		active: 'In progress',
		paused: 'Paused',
		completed: 'Finished',
		stopped: 'Stopped',
		failed: 'Needs attention'
	};
	function historyTone(outcome: RecipeHistoryOutcome): 'success' | 'warning' | 'inactive' {
		if (outcome === 'enrolled') return 'success';
		if (outcome === 'condition_unavailable') return 'warning';
		return 'inactive';
	}
	function formatDateTime(value: string): string {
		return new Date(value).toLocaleString(undefined, {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}
	const quoteHref = (subjectId: string) => resolve('/(app)/quotes/[id]', { id: subjectId });

	const statusBadge: Record<
		RecipeStatus,
		{ tone: 'success' | 'warning' | 'informative' | 'inactive'; label: string }
	> = {
		active: { tone: 'success', label: 'Active' },
		paused: { tone: 'warning', label: 'Paused' },
		draft: { tone: 'informative', label: 'Draft' },
		archived: { tone: 'inactive', label: 'Archived' }
	};

	function formatDate(value: string | null): string {
		if (!value) return '—';
		return new Date(value).toLocaleDateString(undefined, {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		});
	}

	// A short plain-English diff between two frozen versions, oldest → newest, for the Versions tab.
	function describeChanges(older: RecipeVersion, newer: RecipeVersion): string {
		const parts: string[] = [];
		if (older.trigger_key !== newer.trigger_key) parts.push('trigger');
		const countDelta = (a: number, b: number, noun: string) =>
			a === b ? null : `${b > a ? 'added' : 'removed'} ${noun}`;
		const conditions = countDelta(
			older.definition.conditions.length,
			newer.definition.conditions.length,
			'conditions'
		);
		const steps = countDelta(older.definition.steps.length, newer.definition.steps.length, 'steps');
		const stops = countDelta(
			older.definition.stops.length,
			newer.definition.stops.length,
			'stop conditions'
		);
		if (conditions) parts.push(conditions);
		if (steps) parts.push(steps);
		if (stops) parts.push(stops);
		return parts.join(', ');
	}

	// Writes are allowed only when the plan includes Automation, the viewer has the permission, and authority
	// is enabled and not read-only — the same rule the server enforces. Every action below is additionally
	// gated by its own permission (activate vs manage), so a read-only viewer sees a clean, action-free page.
	const access = $derived(accessQuery.data?.status === 'ok' ? accessQuery.data.access : null);
	const canWrite = $derived(!!access && access.authority_state === 'enabled' && !access.read_only);

	const editHref = $derived(resolve('/(app)/settings/automation/[id]/edit', { id: recipeId }));

	// State for the dialogs.
	let activateOpen = $state(false);
	let duplicateOpen = $state(false);
	let duplicateName = $state('');
	let duplicating = $state(false);
	let confirmKind = $state<null | 'archive' | 'restore'>(null);
	let lifecycleBusy = $state(false);

	async function invalidateAll() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: automationRecipeDetailKey(recipeId) }),
			queryClient.invalidateQueries({ queryKey: automationRecipeVersionsKey(recipeId) }),
			queryClient.invalidateQueries({ queryKey: automationRecipeHistoryKey(recipeId) }),
			queryClient.invalidateQueries({ queryKey: automationActivationPreviewKey(recipeId) }),
			queryClient.invalidateQueries({ queryKey: ['settings', 'automation', 'recipes'] }),
			queryClient.invalidateQueries({ queryKey: automationSettingsKey })
		]);
	}

	// Invalidate BEFORE closing the dialog, so the detail page underneath is already showing the new state by
	// the time the dialog disappears — closing first would flash the old Draft/Turn-on state for a beat while
	// the refetch was still in flight.
	async function onActivated(result: ActivateResult) {
		await invalidateAll();
		activateOpen = false;
		toast.success(`Automation turned on (version ${result.version_number}).`);
	}

	const lifecycleLabels: Record<LifecycleAction, { verb: string; done: string }> = {
		pause: { verb: 'pause', done: 'Automation paused.' },
		resume: { verb: 'resume', done: 'Automation resumed.' },
		archive: { verb: 'archive', done: 'Automation archived.' },
		restore: { verb: 'restore', done: 'Automation moved back to a draft.' }
	};

	async function runLifecycle(action: LifecycleAction) {
		const detail = detailQuery.data;
		if (!detail || lifecycleBusy) return;
		lifecycleBusy = true;
		try {
			await setRecipeLifecycle(recipeId, action, detail.draft_revision);
			// Same ordering as activation: refresh the cached data before dismissing the confirm dialog, so
			// there's no beat where the page underneath still shows the pre-action status.
			await invalidateAll();
			confirmKind = null;
			toast.success(lifecycleLabels[action].done);
		} catch (error) {
			if (error instanceof StaleDraftError) {
				await queryClient.invalidateQueries({ queryKey: automationRecipeDetailKey(recipeId) });
				toast.error('This automation just changed', 'We’ve reloaded it — please try again.');
			} else {
				toast.error(
					`We could not ${lifecycleLabels[action].verb} this automation`,
					error instanceof Error ? error.message : undefined
				);
			}
		} finally {
			lifecycleBusy = false;
		}
	}

	function openDuplicate(detail: RecipeDetail) {
		duplicateName = `${detail.name} copy`;
		duplicateOpen = true;
	}

	async function confirmDuplicate() {
		const detail = detailQuery.data;
		if (!detail || duplicating) return;
		const name = duplicateName.trim();
		if (name.length === 0) return;
		duplicating = true;
		try {
			const result = await duplicateRecipe(recipeId, name, detail.draft_revision);
			duplicateOpen = false;
			await queryClient.invalidateQueries({ queryKey: ['settings', 'automation', 'recipes'] });
			toast.success('Automation duplicated.');
			void goto(resolve('/(app)/settings/automation/[id]/edit', { id: result.recipe_id }));
		} catch (error) {
			if (error instanceof StaleDraftError) {
				await queryClient.invalidateQueries({ queryKey: automationRecipeDetailKey(recipeId) });
				toast.error('This automation just changed', 'We’ve reloaded it — please try again.');
				duplicateOpen = false;
			} else {
				toast.error(
					'We could not duplicate this automation',
					error instanceof Error ? error.message : undefined
				);
			}
		} finally {
			duplicating = false;
		}
	}

	// The one green header action, chosen by status. Everything else lives in the More menu.
	type HeaderAction = { label: string; run: () => void } | { label: string; href: string };
	const headerAction = $derived.by((): HeaderAction | null => {
		const detail = detailQuery.data;
		if (!detail || !access || !canWrite) return null;
		if (detail.status === 'draft' && access.can_activate)
			return { label: 'Turn on', run: () => (activateOpen = true) };
		if (detail.status === 'active' && access.can_manage) return { label: 'Edit', href: editHref };
		if (detail.status === 'paused' && access.can_activate)
			return { label: 'Resume', run: () => void runLifecycle('resume') };
		if (detail.status === 'archived' && access.can_manage)
			return { label: 'Restore', run: () => (confirmKind = 'restore') };
		return null;
	});

	const menuItems = $derived.by(() => {
		const detail = detailQuery.data;
		if (!detail || !access || !canWrite) return [];
		const items: {
			label: string;
			icon?: string;
			onSelect: () => void;
			destructive?: boolean;
		}[] = [];
		// Edit is the green action for active recipes; for a draft or paused recipe it belongs in the menu.
		if (access.can_manage && (detail.status === 'draft' || detail.status === 'paused'))
			items.push({ label: 'Edit', icon: pencilIcon, onSelect: () => void goto(editHref) });
		if (access.can_activate && detail.status === 'active')
			items.push({
				label: 'Pause',
				icon: playerPauseIcon,
				onSelect: () => void runLifecycle('pause')
			});
		if (access.can_manage)
			items.push({ label: 'Duplicate', icon: copyIcon, onSelect: () => openDuplicate(detail) });
		if (access.can_activate && detail.status !== 'archived')
			items.push({
				label: 'Archive',
				icon: archiveIcon,
				onSelect: () => (confirmKind = 'archive'),
				destructive: true
			});
		return items;
	});
</script>

{#if accessQuery.isPending}
	<LoadingSkeleton variant="card" rows={2} />
{:else if accessQuery.isError}
	<ErrorState description="Automation could not be loaded." retry={() => accessQuery.refetch()} />
{:else if accessQuery.data.status === 'denied'}
	{#if accessQuery.data.reason === 'not_included'}
		<EmptyState
			icon={robotOffIcon}
			title="Automation isn’t part of your plan"
			description="Automation isn’t included in your current plan. Talk to us if you’d like to add it."
		/>
	{:else}
		<EmptyState
			icon={lockIcon}
			title="You don’t have access to Automation"
			description="Ask an owner or administrator if you need to work with automations."
		/>
	{/if}
{:else if detailQuery.isPending}
	<LoadingSkeleton variant="card" rows={3} />
{:else if detailQuery.isError}
	<ErrorState
		description="This automation could not be loaded. Refresh and try again."
		retry={() => detailQuery.refetch()}
	/>
{:else}
	{@const detail = detailQuery.data}
	{@const suspended = access?.authority_state === 'security_suspended'}
	{@const disabled = access?.authority_state === 'operationally_disabled'}

	<div class="recipe-detail">
		<PageHeader eyebrow="Automation" title={detail.name}>
			{#snippet actions()}
				<div class="recipe-detail__actions">
					{#if headerAction}
						{#if 'href' in headerAction}
							<Button variant="primary" href={headerAction.href}>
								{headerAction.label}
							</Button>
						{:else}
							<Button variant="primary" onclick={headerAction.run} loading={lifecycleBusy}>
								{headerAction.label}
							</Button>
						{/if}
					{/if}
					{#if menuItems.length > 0}
						<DropdownMenu
							items={menuItems}
							triggerLabel="More actions"
							disabled={lifecycleBusy || duplicating}
						/>
					{/if}
				</div>
			{/snippet}
		</PageHeader>

		{#if suspended || disabled}
			<p
				class="recipe-detail__banner"
				class:recipe-detail__banner--suspended={suspended}
				role="status"
			>
				<span class="recipe-detail__banner-icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html alertTriangleIcon}
				</span>
				<span>
					{#if suspended}
						Automation is suspended for your business. You can read this automation, but nothing
						runs and nothing can be changed.
					{:else}
						Automation is temporarily unavailable. You can read this automation, but nothing runs
						right now.
					{/if}
				</span>
			</p>
		{/if}

		<div class="recipe-detail__meta">
			<StatusBadge status={statusBadge[detail.status].tone}>
				{statusBadge[detail.status].label}
			</StatusBadge>
			<Badge>{detail.source === 'preset' ? 'From a preset' : 'Custom'}</Badge>
			{#if detail.active_version}
				<span class="recipe-detail__meta-item">
					Live version {detail.active_version.version_number} · turned on
					{formatDate(detail.active_version.activated_at)}
				</span>
			{/if}
			{#if detail.draft_updated_at}
				<span class="recipe-detail__meta-item">
					Last edited {formatDate(detail.draft_updated_at)}{detail.last_editor_name
						? ` by ${detail.last_editor_name}`
						: ''}
				</span>
			{/if}
		</div>

		<Tabs {tabs} value={activeTab} onChange={selectTab} label="Automation sections">
			<TabPanel value="overview">
				{#if detail.display_definition}
					<SummaryRail name={detail.name} definition={detail.display_definition} />
				{:else}
					<SectionBlock title="Overview" level={2}>
						<p class="recipe-detail__muted">This automation has nothing set up yet.</p>
					</SectionBlock>
				{/if}
				<SectionBlock title="Right now" level={2}>
					<p class="recipe-detail__muted">
						No customers are in this automation right now, and there’s nothing to review.
					</p>
				</SectionBlock>
			</TabPanel>

			<TabPanel value="history">
				{#if historyQuery.isPending}
					<LoadingSkeleton variant="card" rows={2} />
				{:else if historyQuery.isError}
					<ErrorState
						description="This automation’s history could not be loaded."
						retry={() => historyQuery.refetch()}
					/>
				{:else if historyEntries.length === 0}
					<EmptyState
						icon={historyIcon}
						title="Nothing has run yet"
						description="Once this automation is live and starts following up with customers, every step it takes will show up here."
					/>
				{:else}
					<SectionBlock title="History" level={2}>
						<ol class="recipe-detail__history">
							{#each historyEntries as entry (entry.id)}
								<li class="recipe-detail__event">
									<div class="recipe-detail__event-head">
										<StatusBadge status={historyTone(entry.outcome)}>
											{outcomeLabel[entry.outcome]}
										</StatusBadge>
										<span class="recipe-detail__event-time">
											{formatDateTime(entry.happened_at)}
										</span>
									</div>
									<p class="recipe-detail__event-line">
										{#if entry.subject_type === 'quote'}
											<a class="recipe-detail__event-link" href={quoteHref(entry.subject_id)}>
												View quote
											</a>
										{/if}
										{#if entry.enrollment_state}
											<span class="recipe-detail__event-meta">
												{enrollmentStateLabel[entry.enrollment_state]}
												{#if entry.customer_messages_sent != null}
													· {entry.customer_messages_sent}
													{entry.customer_messages_sent === 1 ? 'message' : 'messages'} sent
												{/if}
											</span>
										{/if}
									</p>
									{#if entry.detail}
										<p class="recipe-detail__event-detail">{entry.detail}</p>
									{/if}
								</li>
							{/each}
						</ol>
						{#if historyQuery.hasNextPage}
							<div class="recipe-detail__history-more">
								<Button
									variant="secondary"
									variation="subtle"
									loading={historyQuery.isFetchingNextPage}
									onclick={() => void historyQuery.fetchNextPage()}
								>
									Show more
								</Button>
							</div>
						{/if}
					</SectionBlock>
				{/if}
			</TabPanel>

			<TabPanel value="versions">
				{#if versionsQuery.isPending}
					<LoadingSkeleton variant="card" rows={2} />
				{:else if versionsQuery.isError}
					<ErrorState
						description="This automation’s versions could not be loaded."
						retry={() => versionsQuery.refetch()}
					/>
				{:else if versionsQuery.data.length === 0}
					<EmptyState
						icon={historyIcon}
						title="No versions yet"
						description="A version is saved every time you turn this automation on. None have been saved yet."
					/>
				{:else}
					<SectionBlock title="Versions" level={2}>
						<ol class="recipe-detail__versions">
							{#each versionsQuery.data as version, index (version.id)}
								{@const isCurrent =
									detail.active_version?.version_number === version.version_number}
								{@const older = versionsQuery.data[index + 1]}
								{@const changes = older ? describeChanges(older, version) : ''}
								<li class="recipe-detail__version">
									<div class="recipe-detail__version-head">
										<span class="recipe-detail__version-number"
											>Version {version.version_number}</span
										>
										{#if isCurrent}
											<StatusBadge status="success">Live</StatusBadge>
										{/if}
									</div>
									<p class="recipe-detail__version-meta">
										Turned on {formatDate(version.activated_at)}{version.activated_by_name
											? ` by ${version.activated_by_name}`
											: ''}
									</p>
									<p class="recipe-detail__version-summary">
										When: {triggerLabel(version.trigger_key)} ·
										{version.definition.steps.length}
										{version.definition.steps.length === 1 ? 'step' : 'steps'} ·
										{version.definition.stops.length}
										stop {version.definition.stops.length === 1 ? 'condition' : 'conditions'}
									</p>
									{#if older && changes}
										<p class="recipe-detail__version-diff">
											Changed from v{older.version_number}: {changes}
										</p>
									{/if}
								</li>
							{/each}
						</ol>
					</SectionBlock>
				{/if}
			</TabPanel>
		</Tabs>
	</div>

	<ActivationImpactDialog
		open={activateOpen}
		{recipeId}
		onClose={() => (activateOpen = false)}
		{onActivated}
	/>

	<ConfirmDialog
		open={confirmKind === 'archive'}
		title="Archive this automation?"
		tone="critical"
		icon={archiveIcon}
		confirmLabel="Archive"
		destructive
		loading={lifecycleBusy}
		onConfirm={() => void runLifecycle('archive')}
		onClose={() => (confirmKind = null)}
	>
		Archiving turns this automation off and makes it read-only. You can restore it later as a fresh
		draft.
	</ConfirmDialog>

	<ConfirmDialog
		open={confirmKind === 'restore'}
		title="Restore this automation?"
		confirmLabel="Restore"
		loading={lifecycleBusy}
		onConfirm={() => void runLifecycle('restore')}
		onClose={() => (confirmKind = null)}
	>
		Restoring brings this automation back as a new draft you can edit. Its saved versions are kept.
	</ConfirmDialog>

	{#if duplicateOpen}
		<Dialog
			open={duplicateOpen}
			title="Duplicate automation"
			size="small"
			onClose={() => (duplicateOpen = false)}
		>
			<div class="recipe-detail__duplicate">
				<label class="recipe-detail__duplicate-label" for="duplicate-name">Name for the copy</label>
				<Input id="duplicate-name" bind:value={duplicateName} maxlength={120} />
				<p class="recipe-detail__muted">
					The copy starts as its own draft. It won’t be live until you turn it on.
				</p>
			</div>
			<div class="recipe-detail__duplicate-actions">
				<Button
					variant="secondary"
					variation="subtle"
					onclick={() => (duplicateOpen = false)}
					disabled={duplicating}
				>
					Cancel
				</Button>
				<Button
					variation="work"
					onclick={confirmDuplicate}
					loading={duplicating}
					disabled={duplicateName.trim().length === 0}
				>
					Duplicate
				</Button>
			</div>
		</Dialog>
	{/if}
{/if}

<style lang="scss">
	.recipe-detail {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__banner {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
		}
		&__banner--suspended {
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
		&__banner-icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			margin-top: var(--space-smallest);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__meta {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
		&__meta-item {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-style: italic;
		}

		&__versions {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__version {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}
		&__version-head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}
		&__version-number {
			color: var(--color-heading);
			font-weight: 600;
		}
		&__version-meta,
		&__version-summary,
		&__version-diff {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__version-diff {
			color: var(--color-text);
		}

		&__history {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__event {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}
		&__event-head {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}
		&__event-time {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__event-line {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
		}
		&__event-link {
			color: var(--color-link);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}
		&__event-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__event-detail {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}
		&__history-more {
			display: flex;
			justify-content: center;
			margin-top: var(--space-base);
		}

		&__duplicate {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}
		&__duplicate-label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__duplicate-actions {
			display: flex;
			flex-wrap: wrap;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-large);
		}
	}
</style>
