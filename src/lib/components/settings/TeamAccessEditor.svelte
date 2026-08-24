<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchTeamMemberAccess,
		saveTeamMemberAccess,
		saveTeamMemberRole,
		teamMemberAccessKey,
		teamMemberKey,
		type TeamAccessEditor,
		type TeamAccessAdjustment,
		TeamWriteError
	} from '$lib/team/api';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';

	let { userId }: { userId: string } = $props();

	const queryClient = useQueryClient();
	const actorUserId = $derived(page.data.user?.id ?? '');
	let revealed = $state(false);
	let roleDraft = $state('');
	let keepAdjustments = $state(true);
	let editingPermissions = $state(false);
	let adjustmentDraft = $state<Record<string, 'grant' | 'deny'>>({});
	let savingRole = $state(false);
	let savingPermissions = $state(false);
	let error = $state('');
	let stale = $state(false);

	const accessQuery = createQuery(() => ({
		queryKey: teamMemberAccessKey(actorUserId, userId),
		queryFn: () => fetchTeamMemberAccess(userId),
		enabled: revealed && Boolean(actorUserId),
		staleTime: 30_000
	}));
	const access = $derived(accessQuery.data);
	const canEdit = $derived(Boolean(access?.member.can_edit && actorUserId !== userId));
	const canAssignAdministrator = $derived(page.data.organization?.role === 'owner');
	const hasRoleChange = $derived(Boolean(access && roleDraft && roleDraft !== access.member.role));
	const selectedRole = $derived(access?.roles.find((role) => role.id === roleDraft));
	const roleAdjustmentPreview = $derived.by(() => {
		if (!access || !hasRoleChange || !selectedRole) return [];
		const defaults = new Set(selectedRole.default_control_ids);
		return access.capabilities
			.flatMap((capability) => capability.controls)
			.filter((control) => control.adjustment)
			.filter(
				(control) =>
					!keepAdjustments ||
					(control.adjustment === 'grant' && defaults.has(control.id)) ||
					(control.adjustment === 'deny' && !defaults.has(control.id))
			)
			.map((control) => control.label);
	});
	const retainedAdjustmentPreview = $derived.by(() => {
		if (!access || !hasRoleChange || !selectedRole || !keepAdjustments) return [];
		const defaults = new Set(selectedRole.default_control_ids);
		return access.capabilities
			.flatMap((capability) => capability.controls)
			.filter((control) => control.adjustment)
			.filter(
				(control) =>
					!(
						(control.adjustment === 'grant' && defaults.has(control.id)) ||
						(control.adjustment === 'deny' && !defaults.has(control.id))
					)
			)
			.map((control) => control.label);
	});
	const permissionChanges = $derived(
		Object.entries(adjustmentDraft).map(([control_id, override_state]) => ({
			control_id,
			override_state
		})) satisfies TeamAccessAdjustment[]
	);
	const hasPermissionChanges = $derived.by(() => {
		if (!access) return false;
		return JSON.stringify(permissionChanges) !== JSON.stringify(savedAdjustments(access));
	});

	function savedAdjustments(editor: TeamAccessEditor): TeamAccessAdjustment[] {
		return editor.capabilities
			.flatMap((capability) => capability.controls)
			.flatMap((control) =>
				control.adjustment ? [{ control_id: control.id, override_state: control.adjustment }] : []
			)
			.sort((left, right) => left.control_id.localeCompare(right.control_id));
	}

	function beginRoleEdit() {
		if (!access) return;
		roleDraft = access.member.role;
		keepAdjustments = true;
		error = '';
		stale = false;
	}

	function cancelRoleEdit() {
		roleDraft = '';
		keepAdjustments = true;
		error = '';
		stale = false;
	}

	function beginPermissionsEdit() {
		if (!access) return;
		adjustmentDraft = Object.fromEntries(
			savedAdjustments(access).map((item) => [item.control_id, item.override_state])
		);
		editingPermissions = true;
		error = '';
		stale = false;
	}

	function cancelPermissionsEdit() {
		adjustmentDraft = {};
		editingPermissions = false;
		error = '';
		stale = false;
	}

	function setControl(control: { id: string; included_in_role: boolean }, checked: boolean) {
		const next = { ...adjustmentDraft };
		if (checked === control.included_in_role) delete next[control.id];
		else next[control.id] = checked ? 'grant' : 'deny';
		adjustmentDraft = next;
	}

	async function prefetch() {
		await queryClient.prefetchQuery({
			queryKey: teamMemberAccessKey(actorUserId, userId),
			queryFn: () => fetchTeamMemberAccess(userId),
			staleTime: 30_000
		});
	}

	async function refreshAccess() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: teamMemberAccessKey(actorUserId, userId) }),
			queryClient.invalidateQueries({ queryKey: teamMemberKey(actorUserId, userId) }),
			queryClient.invalidateQueries({ queryKey: ['team', 'directory'] })
		]);
	}

	async function reloadLatest() {
		await queryClient.fetchQuery({
			queryKey: teamMemberAccessKey(actorUserId, userId),
			queryFn: () => fetchTeamMemberAccess(userId),
			staleTime: 0
		});
		cancelRoleEdit();
		cancelPermissionsEdit();
	}

	async function saveRole() {
		if (!access || !hasRoleChange || savingRole) return;
		savingRole = true;
		error = '';
		stale = false;
		try {
			await saveTeamMemberRole(userId, {
				role: roleDraft as Exclude<typeof access.member.role, 'owner'>,
				keep_adjustments: keepAdjustments,
				expected_access_revision: access.member.access_revision
			});
			cancelRoleEdit();
			await refreshAccess();
		} catch (reason) {
			stale = reason instanceof TeamWriteError && reason.stale;
			error = reason instanceof Error ? reason.message : 'The employee role could not be changed.';
		} finally {
			savingRole = false;
		}
	}

	async function savePermissions() {
		if (!access || !hasPermissionChanges || savingPermissions) return;
		savingPermissions = true;
		error = '';
		stale = false;
		try {
			await saveTeamMemberAccess(userId, {
				adjustments: permissionChanges,
				expected_access_revision: access.member.access_revision
			});
			cancelPermissionsEdit();
			await refreshAccess();
		} catch (reason) {
			stale = reason instanceof TeamWriteError && reason.stale;
			error =
				reason instanceof Error ? reason.message : 'The permission adjustments could not be saved.';
		} finally {
			savingPermissions = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Role & access" icon={shieldLockIcon} level={2}>
	{#snippet actions()}
		{#if !revealed}
			<Button
				variant="secondary"
				variation="subtle"
				size="small"
				onhover={() => void prefetch()}
				onclick={() => (revealed = true)}
			>
				Manage access
			</Button>
		{/if}
	{/snippet}

	{#if !revealed}
		<p class="team-access-editor__summary">
			Open this section to review or change this person’s role and access.
		</p>
	{:else if accessQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading access" rows={3} />
	{:else if accessQuery.isError}
		<ErrorState
			description="That person’s access could not be loaded."
			retry={() => accessQuery.refetch()}
		/>
	{:else if access}
		{#if stale}
			<div class="team-access-editor__conflict" role="alert">
				<p>Someone else changed this person’s access while you were editing.</p>
				<button type="button" onclick={() => void reloadLatest()}>Reload latest access</button>
			</div>
		{/if}
		{#if error}<p class="team-access-editor__error" role="alert">{error}</p>{/if}

		{#if !canEdit}
			<p class="team-access-editor__summary">
				{actorUserId === userId
					? 'People cannot change their own role or access.'
					: access.member.cannot_edit_reason}
			</p>
		{:else}
			<section class="team-access-editor__section" aria-labelledby="team-role-heading">
				<div class="team-access-editor__section-header">
					<div>
						<h3 id="team-role-heading">Role</h3>
						<p>A role is the starting point for this person’s access.</p>
					</div>
					{#if !roleDraft}
						<Button variant="secondary" variation="subtle" size="small" onclick={beginRoleEdit}
							>Change role</Button
						>
					{/if}
				</div>

				{#if roleDraft}
					<label class="team-access-editor__role-picker" for="team-member-role">
						<span>Role</span>
						<select id="team-member-role" bind:value={roleDraft} disabled={savingRole}>
							{#each access.roles.filter((role) => role.id !== 'admin' || canAssignAdministrator) as role (role.id)}
								<option value={role.id} disabled={!role.available}>{role.label}</option>
							{/each}
						</select>
					</label>
					{#if selectedRole}<p class="team-access-editor__preview">{selectedRole.summary}</p>{/if}
					{#if hasRoleChange}
						<fieldset class="team-access-editor__choice">
							<legend>Individual adjustments</legend>
							<label
								><input
									type="radio"
									name="team-adjustments"
									bind:group={keepAdjustments}
									value={false}
								/> Use the new role’s standard access</label
							>
							<label
								><input
									type="radio"
									name="team-adjustments"
									bind:group={keepAdjustments}
									value={true}
								/> Keep compatible individual adjustments</label
							>
							{#if roleAdjustmentPreview.length}
								<p class="team-access-editor__preview">
									These adjustments will be removed because they no longer change access:
									{roleAdjustmentPreview.join(', ')}.
								</p>
							{/if}
							{#if retainedAdjustmentPreview.length}
								<p class="team-access-editor__preview">
									These individual adjustments will stay: {retainedAdjustmentPreview.join(', ')}.
								</p>
							{/if}
						</fieldset>
					{/if}
					<div class="team-access-editor__actions">
						<Button onclick={() => void saveRole()} loading={savingRole} disabled={!hasRoleChange}
							>Save role</Button
						>
						<Button
							variant="secondary"
							variation="subtle"
							onclick={cancelRoleEdit}
							disabled={savingRole}>Cancel</Button
						>
					</div>
				{:else}
					<p class="team-access-editor__role-name">
						{access.roles.find((role) => role.id === access.member.role)?.label}
					</p>
					{#if access.member.is_adjusted}<span class="team-access-editor__adjusted">Adjusted</span
						>{/if}
				{/if}
			</section>

			<section class="team-access-editor__section" aria-labelledby="team-permissions-heading">
				<div class="team-access-editor__section-header">
					<div>
						<h3 id="team-permissions-heading">Individual access</h3>
						<p>Fine-tune access without creating a custom role.</p>
					</div>
					{#if !editingPermissions}
						<Button
							variant="secondary"
							variation="subtle"
							size="small"
							onclick={beginPermissionsEdit}>Adjust access</Button
						>
					{/if}
				</div>

				{#each access.capabilities as capability (capability.id)}
					<div class="team-access-editor__capability">
						<div class="team-access-editor__capability-heading">
							<div>
								<h4>{capability.name}</h4>
								<p>{capability.description}</p>
							</div>
							<Popover.Root>
								<Popover.Trigger
									class="team-access-editor__help"
									aria-label={`More about ${capability.name}`}
								>
									{@html infoIcon}
								</Popover.Trigger>
								<Popover.Portal>
									<Popover.Content class="team-access-editor__popover" sideOffset={8}>
										<strong>{capability.name}</strong>
										<p>
											{capability.description} Each option below explains a practical action it allows.
										</p>
									</Popover.Content>
								</Popover.Portal>
							</Popover.Root>
						</div>
						<div class="team-access-editor__controls">
							{#each capability.controls as control (control.id)}
								<Checkbox
									id={`team-access-${control.id}`}
									label={control.label}
									description={control.available ? control.example : 'Not included in your plan.'}
									checked={editingPermissions
										? (adjustmentDraft[control.id] ?? control.adjustment) === 'grant' ||
											((adjustmentDraft[control.id] ?? control.adjustment) === null &&
												control.included_in_role)
										: control.effective}
									disabled={!editingPermissions || !control.available || savingPermissions}
									onchange={(checked) => setControl(control, checked)}
								/>
							{/each}
						</div>
					</div>
				{/each}

				{#if editingPermissions}
					<div class="team-access-editor__actions">
						<Button
							onclick={() => void savePermissions()}
							loading={savingPermissions}
							disabled={!hasPermissionChanges}>Save access</Button
						>
						<Button
							variant="secondary"
							variation="subtle"
							onclick={cancelPermissionsEdit}
							disabled={savingPermissions}>Cancel</Button
						>
					</div>
				{/if}
			</section>
		{/if}
	{/if}
</SectionBlock>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.team-access-editor__summary,
	.team-access-editor__section-header p,
	.team-access-editor__capability-heading p,
	:global(.team-access-editor__popover p) {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.team-access-editor__conflict,
	.team-access-editor__section,
	.team-access-editor__capability {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.team-access-editor__conflict {
		align-items: flex-start;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}

	.team-access-editor__conflict p,
	.team-access-editor__error {
		margin: 0;
	}

	.team-access-editor__conflict button {
		color: inherit;
		font: inherit;
		font-weight: 700;
		text-decoration: underline;
	}

	.team-access-editor__conflict button:focus-visible,
	:global(.team-access-editor__help:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	.team-access-editor__error {
		color: var(--color-critical);
	}

	.team-access-editor__section {
		padding-top: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}

	.team-access-editor__section-header,
	.team-access-editor__capability-heading,
	.team-access-editor__actions {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.team-access-editor__section h3,
	.team-access-editor__capability h4 {
		margin: 0 0 var(--space-smaller);
		color: var(--color-heading);
	}

	.team-access-editor__role-name {
		margin: 0;
		color: var(--color-heading);
		font-weight: 700;
	}

	.team-access-editor__adjusted {
		display: inline-flex;
		width: fit-content;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-small);
	}

	.team-access-editor__role-picker,
	.team-access-editor__choice {
		display: grid;
		gap: var(--space-small);
	}

	.team-access-editor__role-picker > span,
	.team-access-editor__choice legend {
		color: var(--color-heading);
		font-weight: 700;
	}

	.team-access-editor__role-picker select {
		min-height: 40px;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
	}

	.team-access-editor__role-picker select:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	.team-access-editor__choice {
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.team-access-editor__choice label {
		display: flex;
		gap: var(--space-small);
		color: var(--color-text);
	}

	.team-access-editor__preview {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.team-access-editor__capability {
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.team-access-editor__capability-heading > div {
		min-width: 0;
	}

	:global(.team-access-editor__help) {
		display: grid;
		width: 32px;
		height: 32px;
		flex: 0 0 auto;
		place-items: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-interactive--subtle);
		background: transparent;
		cursor: pointer;
	}

	:global(.team-access-editor__help:hover) {
		background: var(--color-surface--hover);
	}

	:global(.team-access-editor__help svg) {
		width: 20px;
		height: 20px;
	}

	:global(.team-access-editor__popover) {
		z-index: var(--elevation-tooltip);
		max-width: 350px;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.team-access-editor__popover strong) {
		display: block;
		margin-bottom: var(--space-small);
		color: var(--color-heading);
	}

	.team-access-editor__controls {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}

	@media (max-width: 639px) {
		.team-access-editor__section-header,
		.team-access-editor__capability-heading,
		.team-access-editor__actions {
			flex-direction: column;
		}

		.team-access-editor__controls {
			grid-template-columns: 1fr;
		}
	}
</style>
