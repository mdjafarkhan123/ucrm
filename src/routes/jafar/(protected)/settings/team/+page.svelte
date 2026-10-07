<script lang="ts">
	import { resolve } from '$app/paths';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import adjustmentsIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';
	import mailForwardIcon from '@tabler/icons/outline/mail-forward.svg?raw';
	import userMinusIcon from '@tabler/icons/outline/user-minus.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import TeamMemberAccessPanel from '$lib/components/jafar/team/TeamMemberAccessPanel.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { jafarTeamKey, jafarTeamMemberAccessKey } from '$lib/jafar/query-keys';
	import {
		JAFAR_AREA_LABELS,
		TEAM_ROLES,
		TEAM_ROLE_AREAS,
		TEAM_ROLE_LABELS,
		type JafarArea,
		type TeamRole
	} from '$lib/jafar/team-access';
	import {
		TeamRequestError,
		fetchTeam,
		fetchTeamMemberAccess,
		inviteTeammate,
		removeTeammate,
		resendTeamInvitation,
		type TeamMember
	} from '$lib/jafar/team';

	// Jafar's team (D1, D2, ADR 0008): who works in the panel, waiting invitations, what each role opens,
	// and each teammate's own access, managed in a side panel that loads when its button is reached.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const teamQuery = createQuery(() => ({ queryKey: jafarTeamKey, queryFn: fetchTeam }));
	const members = $derived(teamQuery.data ?? []);

	function roleAccess(role: TeamRole) {
		return Object.entries(TEAM_ROLE_AREAS[role]).map(([area, level]) => ({
			label: JAFAR_AREA_LABELS[area as JafarArea],
			level: level === 'work' ? 'can change' : 'view only'
		}));
	}

	// Manage access
	let accessTarget = $state<TeamMember | null>(null);

	function prefetchAccess(member: TeamMember) {
		void queryClient.prefetchQuery({
			queryKey: jafarTeamMemberAccessKey(member.id),
			queryFn: () => fetchTeamMemberAccess(member.id),
			staleTime: 30_000
		});
	}

	const columns: DataTableColumn[] = [
		{ key: 'person', label: 'Person' },
		{ key: 'role', label: 'Role' },
		{ key: 'status', label: 'Status' }
	];

	const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });

	function invitationExpired(member: TeamMember) {
		return (
			member.status === 'invited' &&
			member.invitation_expires_at !== null &&
			new Date(member.invitation_expires_at).getTime() <= Date.now()
		);
	}

	function displayName(member: TeamMember) {
		return member.full_name ?? member.email;
	}

	// Invite
	let inviteOpen = $state(false);
	let inviteEmail = $state('');
	let inviteRole = $state<TeamRole>('sales');
	let inviteError = $state('');
	let inviteFieldErrors = $state<Record<string, string>>({});

	function openInvite() {
		inviteEmail = '';
		inviteRole = 'sales';
		inviteError = '';
		inviteFieldErrors = {};
		inviteOpen = true;
	}

	const invite = createMutation(() => ({
		mutationFn: inviteTeammate,
		onSuccess: ({ member }) => {
			inviteOpen = false;
			toast.success(`Invitation sent to ${member.email}.`);
		},
		onError: (error: Error) => {
			if (error instanceof TeamRequestError && error.emailFailed) {
				// Saved without its email: the row is there to resend from.
				inviteOpen = false;
				toast.error(error.message);
				return;
			}
			inviteError = error.message;
			inviteFieldErrors = error instanceof TeamRequestError ? error.fieldErrors : {};
		},
		onSettled: () => queryClient.invalidateQueries({ queryKey: jafarTeamKey })
	}));

	function submitInvite(event: SubmitEvent) {
		event.preventDefault();
		inviteError = '';
		inviteFieldErrors = {};
		invite.mutate({ email: inviteEmail.trim(), role: inviteRole });
	}

	// Resend
	const resend = createMutation(() => ({
		mutationFn: resendTeamInvitation,
		onSuccess: ({ member }) => toast.success(`A new invitation is on its way to ${member.email}.`),
		onError: (error: Error) => toast.error(error.message),
		onSettled: () => queryClient.invalidateQueries({ queryKey: jafarTeamKey })
	}));

	// Remove or cancel
	let removeTarget = $state<TeamMember | null>(null);

	const remove = createMutation(() => ({
		mutationFn: (member: TeamMember) => removeTeammate(member.id),
		onSuccess: (_result, member) => {
			removeTarget = null;
			toast.success(
				member.status === 'invited'
					? `Invitation for ${member.email} cancelled.`
					: `${displayName(member)} was removed and signed out.`
			);
		},
		onError: (error: Error) => toast.error(error.message),
		onSettled: () => queryClient.invalidateQueries({ queryKey: jafarTeamKey })
	}));

	function menuItems(member: TeamMember) {
		if (member.status === 'invited') {
			return [
				{
					label: 'Resend invitation',
					icon: mailForwardIcon,
					disabled: resend.isPending,
					onSelect: () => resend.mutate(member.id)
				},
				{
					label: 'Cancel invitation',
					icon: userMinusIcon,
					destructive: true,
					onSelect: () => (removeTarget = member)
				}
			];
		}
		return [
			{
				label: 'Remove from team',
				icon: userMinusIcon,
				destructive: true,
				onSelect: () => (removeTarget = member)
			}
		];
	}
</script>

<svelte:head><title>Team & access · Settings · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<Breadcrumbs
	items={[{ label: 'Settings', href: resolve('/jafar/settings') }, { label: 'Team & access' }]}
/>

<div class="jafar-team">
	<PageHeader
		eyebrow="Team & access"
		title="Team"
		description="The people who work in this panel with you. Each one signs in at the same address with their own email and password."
	>
		{#snippet actions()}
			<Button onclick={openInvite}
				><span class="jafar-team__icon" aria-hidden="true">{@html userPlusIcon}</span>Invite
				teammate</Button
			>
		{/snippet}
	</PageHeader>

	<div class="jafar-team__layout">
		<div class="jafar-team__main">
			{#if teamQuery.isPending}
				<LoadingSkeleton variant="table" label="Loading your team" rows={3} />
			{:else if teamQuery.isError && !teamQuery.data}
				<ErrorState
					title="Your team could not be loaded"
					description={teamQuery.error.message}
					retry={() => teamQuery.refetch()}
				/>
			{:else if members.length === 0}
				<EmptyState
					icon={usersIcon}
					title="It's just you for now"
					description="Invite a teammate and they'll get an email to set their password. Anything not assigned to someone stays with you."
				>
					{#snippet action()}
						<Button onclick={openInvite}>Invite teammate</Button>
					{/snippet}
				</EmptyState>
			{:else}
				<DataTable {columns} items={members} rowId={(member) => member.id} caption="Your team">
					{#snippet row(member: TeamMember)}
						<th scope="row">
							<div class="jafar-team__person">
								<Avatar
									id={member.id}
									name={displayName(member)}
									src={member.avatar_url}
									size="small"
								/>
								<div class="jafar-team__person-text">
									<strong>{displayName(member)}</strong>
									{#if member.full_name}<span>{member.email}</span>{/if}
									<span class="jafar-team__person-role">{TEAM_ROLE_LABELS[member.role]}</span>
								</div>
							</div>
						</th>
						<td class="jafar-team__role"
							><Badge dot={false}>{TEAM_ROLE_LABELS[member.role]}</Badge></td
						>
						<td>
							{#if member.status === 'active'}
								<StatusBadge status="success">Active</StatusBadge>
							{:else if invitationExpired(member)}
								<div class="jafar-team__status">
									<StatusBadge status="critical">Invitation expired</StatusBadge>
									<span>Resend to give them a new link</span>
								</div>
							{:else}
								<div class="jafar-team__status">
									<StatusBadge status="warning">Invited</StatusBadge>
									<span>Sent {dateFormat.format(new Date(member.invited_at))}</span>
								</div>
							{/if}
						</td>
					{/snippet}
					{#snippet rowActions(member: TeamMember)}
						<div class="jafar-team__row-actions">
							<Button
								variant="secondary"
								variation="subtle"
								size="small"
								onhover={() => prefetchAccess(member)}
								onclick={() => (accessTarget = member)}
								><span class="jafar-team__icon" aria-hidden="true">{@html adjustmentsIcon}</span
								><span class="jafar-team__access-label"
									>Manage access<span class="jafar-team__visually-hidden">
										for {displayName(member)}</span
									></span
								></Button
							>
							<DropdownMenu
								items={menuItems(member)}
								triggerLabel={`Actions for ${displayName(member)}`}
								align="end"
							/>
						</div>
					{/snippet}
				</DataTable>
			{/if}
		</div>

		<Card heading="What each role opens" class="jafar-team__roles">
			<ul class="jafar-team__role-list">
				{#each TEAM_ROLES as role (role)}
					<li>
						<strong>{TEAM_ROLE_LABELS[role]}</strong>
						<span
							>{roleAccess(role)
								.map((access) => `${access.label} (${access.level})`)
								.join(' · ')}</span
						>
					</li>
				{/each}
			</ul>
			<p class="jafar-team__note">
				These are starting points. Use Manage access to open more or less for one person, or to turn
				on sensitive actions like confirming payments. Overview, Settings, and the Team always stay
				with you.
			</p>
		</Card>
	</div>
</div>

{#if inviteOpen}
	<Dialog
		open
		title="Invite teammate"
		size="small"
		initialFocusId="jafar-team-invite-email"
		onClose={() => !invite.isPending && (inviteOpen = false)}
	>
		<form class="jafar-team__invite" onsubmit={submitInvite}>
			<p class="jafar-team__invite-copy">
				They'll get an email with a link to set their password. The link lasts seven days.
			</p>
			<Input
				id="jafar-team-invite-email"
				label="Email address"
				type="email"
				required
				maxlength="254"
				bind:value={inviteEmail}
				invalid={Boolean(inviteFieldErrors.email)}
				errorMessage={inviteFieldErrors.email}
				disabled={invite.isPending}
			/>
			<Select
				id="jafar-team-invite-role"
				label="Role"
				required
				bind:value={inviteRole}
				options={TEAM_ROLES.map((role) => ({ value: role, label: TEAM_ROLE_LABELS[role] }))}
				disabled={invite.isPending}
			/>
			<p class="jafar-team__invite-copy">
				{TEAM_ROLE_LABELS[inviteRole]} opens {roleAccess(inviteRole)
					.map((access) => `${access.label} (${access.level})`)
					.join(', ')}.
			</p>
			{#if inviteError && !inviteFieldErrors.email}
				<p class="jafar-team__error" role="alert">{inviteError}</p>
			{/if}
			<div class="jafar-team__invite-actions">
				<Button
					variant="secondary"
					variation="subtle"
					disabled={invite.isPending}
					onclick={() => (inviteOpen = false)}>Cancel</Button
				>
				<Button type="submit" loading={invite.isPending} disabled={!inviteEmail.trim()}
					>Send invitation</Button
				>
			</div>
		</form>
	</Dialog>
{/if}

<TeamMemberAccessPanel
	memberId={accessTarget?.id ?? null}
	memberName={accessTarget ? displayName(accessTarget) : ''}
	onClose={() => (accessTarget = null)}
/>

<ConfirmDialog
	open={removeTarget !== null}
	title={removeTarget?.status === 'invited' ? 'Cancel this invitation?' : 'Remove from your team?'}
	icon={userMinusIcon}
	tone="critical"
	destructive
	confirmLabel={removeTarget?.status === 'invited' ? 'Cancel invitation' : 'Remove and sign out'}
	cancelLabel="Keep"
	loading={remove.isPending}
	onConfirm={() => removeTarget && remove.mutate(removeTarget)}
	onClose={() => !remove.isPending && (removeTarget = null)}
>
	{#if removeTarget?.status === 'invited'}
		<p>The link sent to {removeTarget.email} stops working. You can invite them again later.</p>
	{:else if removeTarget}
		<p>
			{displayName(removeTarget)} is signed out straight away and can no longer sign in. Anything they
			already did stays in the history. You can invite them again later.
		</p>
	{/if}
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.jafar-team {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.jafar-team__layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 320px;
		align-items: start;
		gap: var(--space-large);
	}

	.jafar-team__main {
		min-width: 0;
	}

	.jafar-team__icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.jafar-team__row-actions {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-smaller);
	}

	.jafar-team__visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	.jafar-team__person {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
	}

	.jafar-team__person-text {
		display: flex;
		flex-direction: column;
		min-width: 0;

		strong {
			color: var(--color-heading);
			font-weight: 700;
			overflow-wrap: anywhere;
		}

		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
			overflow-wrap: anywhere;
		}

		.jafar-team__person-role {
			display: none;
		}
	}

	.jafar-team__status {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-smallest);

		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.jafar-team__role-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		li {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}

		strong {
			color: var(--color-heading);
		}

		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
	}

	.jafar-team__note {
		margin: var(--space-base) 0 0;
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.jafar-team__invite {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.jafar-team__invite-copy {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.jafar-team__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.jafar-team__invite-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	@media (max-width: 1023px) {
		.jafar-team__layout {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	// On a phone the role moves under the name, so status and the actions menu stay on screen.
	@media (max-width: 489px) {
		.jafar-team__main :global(th:nth-child(2)),
		.jafar-team__main :global(.jafar-team__role) {
			display: none;
		}

		// A long email wraps instead of pushing status and actions off screen.
		.jafar-team__main :global(tbody th) {
			white-space: normal;
		}

		.jafar-team__person-text .jafar-team__person-role {
			display: block;
		}

		// The access button keeps its icon and spoken name; the words would push the menu off screen.
		.jafar-team__access-label {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}
</style>
