<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import RadioGroup from '$lib/components/ui/RadioGroup.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { jafarTeamKey, jafarTeamMemberAccessKey } from '$lib/jafar/query-keys';
	import {
		AREA_MAX_LEVEL,
		JAFAR_AREAS,
		JAFAR_AREA_LABELS,
		SENSITIVE_ACTIONS,
		SENSITIVE_ACTION_DETAILS,
		TEAM_ROLES,
		TEAM_ROLE_LABELS,
		TEAM_ROLE_AREAS,
		effectiveTeamAccess,
		teamAccessProblem,
		type AreaSetting,
		type JafarArea,
		type SensitiveAction,
		type TeamAccessAdjustments,
		type TeamRole
	} from '$lib/jafar/team-access';
	import {
		TeamRequestError,
		describeTeamHistoryEntry,
		fetchTeamMemberAccess,
		saveTeamMemberAccess,
		type TeamMemberAccessView
	} from '$lib/jafar/team';

	// One teammate's role, areas, sensitive actions, and history (D2, ADR 0008). Nothing saves until Jafar
	// presses Save; the draft is the role plus what differs from it, the same shape the server stores, so a
	// role change can either start from the new role's standard access or carry the differences across
	// (the contractor TeamAccessEditor pattern).
	let {
		memberId,
		memberName,
		onClose
	}: {
		/** The teammate being managed; null keeps the panel closed. */
		memberId: string | null;
		memberName: string;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const accessQuery = createQuery(() => ({
		queryKey: jafarTeamMemberAccessKey(memberId ?? ''),
		queryFn: () => fetchTeamMemberAccess(memberId ?? ''),
		enabled: memberId !== null,
		staleTime: 30_000
	}));
	const view = $derived(memberId ? accessQuery.data : undefined);

	type Draft = { memberId: string; role: TeamRole; adjustments: TeamAccessAdjustments };
	let draft = $state<Draft | null>(null);
	let roleMode = $state<'keep' | 'standard'>('keep');
	/** The adjustments as they were before the role changed, so either answer can be applied again. */
	let adjustmentsBeforeRoleChange = $state<TeamAccessAdjustments | null>(null);
	let stale = $state(false);
	let saveError = $state('');

	function emptyAdjustments(): TeamAccessAdjustments {
		return { areas: {}, actions: [] };
	}

	function startDraft(source: TeamMemberAccessView) {
		draft = {
			memberId: source.member.id,
			role: source.member.role,
			adjustments: {
				areas: { ...source.adjustments.areas },
				actions: [...source.adjustments.actions]
			}
		};
		roleMode = 'keep';
		adjustmentsBeforeRoleChange = null;
		stale = false;
		saveError = '';
	}

	// The first load for this teammate becomes the draft. A background refresh never overwrites edits; a
	// newer save by someone else is caught by the revision check and offered as "Reload latest".
	$effect(() => {
		if (view && draft?.memberId !== view.member.id) startDraft(view);
	});

	const access = $derived(draft ? effectiveTeamAccess(draft.role, draft.adjustments) : null);
	const problem = $derived(access ? teamAccessProblem(access) : null);
	const roleChanged = $derived(Boolean(view && draft && draft.role !== view.member.role));
	const hadAdjustments = $derived(
		Boolean(
			adjustmentsBeforeRoleChange &&
			(Object.keys(adjustmentsBeforeRoleChange.areas).length ||
				adjustmentsBeforeRoleChange.actions.length)
		)
	);
	const dirty = $derived.by(() => {
		if (!view || !draft || !access) return false;
		if (draft.role !== view.member.role) return true;
		const sameAreas = JAFAR_AREAS.every((area) => access.areas[area] === view.access.areas[area]);
		const sameActions =
			access.actions.length === view.access.actions.length &&
			access.actions.every((action) => view.access.actions.includes(action));
		return !(sameAreas && sameActions);
	});

	function applyRoleMode() {
		if (!draft || !adjustmentsBeforeRoleChange) return;
		draft.adjustments =
			roleMode === 'standard'
				? emptyAdjustments()
				: {
						areas: { ...adjustmentsBeforeRoleChange.areas },
						actions: [...adjustmentsBeforeRoleChange.actions]
					};
	}

	function changeRole(next: string) {
		if (!draft || !view) return;
		adjustmentsBeforeRoleChange ??= {
			areas: { ...draft.adjustments.areas },
			actions: [...draft.adjustments.actions]
		};
		draft.role = next as TeamRole;
		if (draft.role === view.member.role) {
			// Back to the saved role: back to exactly what was there.
			draft.adjustments = adjustmentsBeforeRoleChange;
			adjustmentsBeforeRoleChange = null;
			roleMode = 'keep';
			return;
		}
		applyRoleMode();
	}

	function areaSetting(area: JafarArea): AreaSetting {
		return access?.areas[area] ?? 'none';
	}

	function setArea(area: JafarArea, setting: string) {
		if (!draft) return;
		const standard = TEAM_ROLE_AREAS[draft.role][area] ?? 'none';
		const areas = { ...draft.adjustments.areas };
		if (setting === standard) delete areas[area];
		else areas[area] = setting as AreaSetting;
		draft.adjustments.areas = areas;
	}

	function setAction(action: SensitiveAction, on: boolean) {
		if (!draft) return;
		const actions = draft.adjustments.actions.filter((granted) => granted !== action);
		draft.adjustments.actions = on ? [...actions, action] : actions;
	}

	function areaOptions(area: JafarArea) {
		const options = [
			{ value: 'none', label: 'Off' },
			{ value: 'look', label: 'View' }
		];
		if (AREA_MAX_LEVEL[area] === 'work') options.push({ value: 'work', label: 'Change' });
		return options;
	}

	const save = createMutation(() => ({
		mutationFn: () => {
			if (!view || !draft || !access) throw new Error('Nothing to save yet.');
			return saveTeamMemberAccess(view.member.id, {
				role: draft.role,
				areas: access.areas,
				actions: access.actions,
				expected_access_revision: view.member.access_revision
			});
		},
		onSuccess: (saved) => {
			queryClient.setQueryData(jafarTeamMemberAccessKey(saved.member.id), saved);
			toast.success(`Access saved for ${saved.member.full_name ?? saved.member.email}.`);
			draft = null;
			onClose();
		},
		onError: (error: Error) => {
			stale = error instanceof TeamRequestError && error.stale;
			saveError = error.message;
		},
		onSettled: () => queryClient.invalidateQueries({ queryKey: jafarTeamKey, exact: true })
	}));

	async function reloadLatest() {
		if (!memberId) return;
		const latest = await queryClient.fetchQuery({
			queryKey: jafarTeamMemberAccessKey(memberId),
			queryFn: () => fetchTeamMemberAccess(memberId),
			staleTime: 0
		});
		startDraft(latest);
	}

	function close() {
		if (save.isPending) return;
		draft = null;
		onClose();
	}

	const historyFormat = new Intl.DateTimeFormat(undefined, {
		dateStyle: 'medium',
		timeStyle: 'short'
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SidePanel open={memberId !== null} title="Manage access" subtitle={memberName} onClose={close}>
	{#if accessQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading access" rows={4} />
	{:else if accessQuery.isError && !view}
		<ErrorState
			title="This access could not be loaded"
			description={accessQuery.error.message}
			retry={() => accessQuery.refetch()}
		/>
	{:else if view && draft && access}
		<div class="team-member-access">
			{#if stale}
				<Banner type="warning">
					Someone saved a newer version of this access while you were editing.
					{#snippet action()}
						<Button variant="secondary" size="small" onclick={() => void reloadLatest()}
							>Reload latest</Button
						>
					{/snippet}
				</Banner>
			{:else if saveError}
				<Banner type="error">{saveError}</Banner>
			{/if}

			<section class="team-member-access__section" aria-labelledby="team-member-access-role">
				<h3 id="team-member-access-role" class="team-member-access__heading">Role</h3>
				<Select
					id="team-member-access-role-select"
					label="Role"
					value={draft.role}
					options={TEAM_ROLES.map((role) => ({ value: role, label: TEAM_ROLE_LABELS[role] }))}
					onchange={changeRole}
					disabled={save.isPending}
				/>
				{#if roleChanged && hadAdjustments}
					<RadioGroup
						label={`${memberName} has access set differently from their role. For the new role:`}
						bind:value={roleMode}
						options={[
							{ value: 'keep', label: 'Keep my changes' },
							{ value: 'standard', label: `Use ${TEAM_ROLE_LABELS[draft.role]}’s standard access` }
						]}
						onchange={applyRoleMode}
						disabled={save.isPending}
					/>
				{/if}
			</section>

			<section class="team-member-access__section" aria-labelledby="team-member-access-areas">
				<div>
					<h3 id="team-member-access-areas" class="team-member-access__heading">Areas</h3>
					<p class="team-member-access__hint">
						View opens the pages to look. Change also lets them add and edit there.
					</p>
				</div>
				<ul class="team-member-access__areas">
					{#each JAFAR_AREAS as area (area)}
						{@const standard = TEAM_ROLE_AREAS[draft.role][area] ?? 'none'}
						<li class="team-member-access__area">
							<span class="team-member-access__area-name">
								{JAFAR_AREA_LABELS[area]}
								{#if areaSetting(area) !== standard}
									<span class="team-member-access__adjusted">Changed from role</span>
								{/if}
							</span>
							<SegmentedControl
								size="small"
								ariaLabel={`${JAFAR_AREA_LABELS[area]} access`}
								value={areaSetting(area)}
								options={areaOptions(area)}
								onchange={(setting) => setArea(area, setting)}
								disabled={save.isPending}
							/>
						</li>
					{/each}
				</ul>
				{#if problem}
					<p class="team-member-access__problem" role="alert">{problem}</p>
				{/if}
			</section>

			<section class="team-member-access__section" aria-labelledby="team-member-access-actions">
				<div>
					<h3 id="team-member-access-actions" class="team-member-access__heading">
						Sensitive actions
					</h3>
					<p class="team-member-access__hint">
						Off for everyone until you turn them on. Each one needs its area open.
					</p>
				</div>
				<div class="team-member-access__actions">
					{#each SENSITIVE_ACTIONS as action (action)}
						{@const details = SENSITIVE_ACTION_DETAILS[action]}
						{@const areaOpen = Boolean(access.areas[details.area])}
						<Checkbox
							id={`team-member-access-${action}`}
							label={details.label}
							description={areaOpen
								? details.description
								: `Open ${JAFAR_AREA_LABELS[details.area]} first. ${details.description}`}
							checked={access.actions.includes(action)}
							disabled={!areaOpen || save.isPending}
							onchange={(checked) => setAction(action, checked)}
						/>
					{/each}
				</div>
				<div class="team-member-access__owner-only">
					<span class="team-member-access__owner-icon" aria-hidden="true">{@html lockIcon}</span>
					<p>
						Always yours, whatever is turned on: managing the team, Settings, and anything that asks
						for your password — billing, closing or pausing an account, text-message credit, refunds
						and holds, and recovering a client's administrator.
					</p>
				</div>
			</section>

			<section class="team-member-access__section" aria-labelledby="team-member-access-history">
				<h3 id="team-member-access-history" class="team-member-access__heading">History</h3>
				{#if view.history.length === 0}
					<p class="team-member-access__hint">Nothing recorded yet.</p>
				{:else}
					<ol class="team-member-access__history">
						{#each view.history as entry (entry.id)}
							<li>
								<ul class="team-member-access__history-lines">
									{#each describeTeamHistoryEntry(entry) as line, index (index)}
										<li>{line}</li>
									{/each}
								</ul>
								<span class="team-member-access__history-meta">
									{entry.actor_email} · {historyFormat.format(new Date(entry.created_at))}
								</span>
							</li>
						{/each}
					</ol>
				{/if}
			</section>
		</div>
	{/if}

	{#snippet footer()}
		<div class="team-member-access__footer">
			<Button variant="secondary" variation="subtle" disabled={save.isPending} onclick={close}
				>Cancel</Button
			>
			<Button
				loading={save.isPending}
				disabled={!dirty || Boolean(problem) || stale}
				onclick={() => {
					saveError = '';
					save.mutate();
				}}>Save access</Button
			>
		</div>
	{/snippet}
</SidePanel>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.team-member-access {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.team-member-access__section {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		& + & {
			padding-top: var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.team-member-access__heading {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.team-member-access__hint {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.team-member-access__areas {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.team-member-access__area {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) 0;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.team-member-access__area-name {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
		color: var(--color-text);
		font-weight: 600;
	}

	.team-member-access__adjusted {
		width: fit-content;
		padding: 0 var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-informative);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
	}

	.team-member-access__problem {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.team-member-access__actions {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.team-member-access__owner-only {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		p {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
	}

	.team-member-access__owner-icon {
		display: inline-grid;
		flex: none;
		place-items: center;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.team-member-access__history {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		> li {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding-left: var(--space-base);
			border-left: var(--border-thick) solid var(--color-border);
		}
	}

	.team-member-access__history-lines {
		margin: 0;
		padding: 0;
		list-style: none;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.team-member-access__history-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		overflow-wrap: anywhere;
	}

	.team-member-access__footer {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
