<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		fetchTeamDirectory,
		createTeamInvitation,
		TeamInvitationWriteError,
		teamDirectoryKey,
		type TeamDirectoryFilters,
		type TeamDirectoryMember,
		type TeamDirectoryPage,
		type TeamMemberRole,
		type TeamMemberStatus
	} from '$lib/team/api';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import armchairIcon from '@tabler/icons/outline/armchair.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import usersGroupPageIcon from '@tabler/icons/outline/users-group.svg?raw';

	const queryClient = useQueryClient();
	const actorUserId = $derived(page.data.user?.id ?? '');
	const toast = getToastManager();
	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<TeamMemberStatus | ''>('');
	let inviteOpen = $state(false);
	let inviteEmail = $state('');
	let inviteRole = $state<Exclude<TeamMemberRole, 'owner'>>('field');
	let inviteSaving = $state(false);
	let inviteError = $state('');
	let inviteFieldErrors = $state<Record<string, string>>({});

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived<TeamDirectoryFilters>({
		search: debouncedSearch,
		status
	});
	const teamQuery = createInfiniteQuery(() => ({
		queryKey: teamDirectoryKey(actorUserId, filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchTeamDirectory(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: TeamDirectoryPage) => lastPage.next_cursor ?? undefined,
		staleTime: 30_000,
		enabled: Boolean(actorUserId)
	}));

	const members = $derived(teamQuery.data?.pages.flatMap((page) => page.members) ?? []);
	const seats = $derived(teamQuery.data?.pages[0]?.seats);
	const hasFilters = $derived(Boolean(search.trim() || status));
	const seatSummary = $derived.by(() => {
		if (!seats) return '';
		return seats.is_unlimited
			? `${seats.used} ${seats.used === 1 ? 'seat' : 'seats'} used`
			: `${seats.used} of ${seats.limit} ${seats.limit === 1 ? 'seat' : 'seats'} used`;
	});

	const columns: DataTableColumn[] = [
		{ key: 'member', label: 'Team member', width: '29%' },
		{ key: 'role', label: 'Role', width: '17%' },
		{ key: 'work_details', label: 'Work details' },
		{ key: 'status', label: 'Status', width: '21%' },
		{ key: 'open', label: 'Open member', hideLabel: true, width: '40px' }
	];

	function setStatus(value: string) {
		status = value as TeamMemberStatus | '';
	}

	function clearFilters() {
		search = '';
		debouncedSearch = '';
		status = '';
	}

	function closeInvite(force = false) {
		if (inviteSaving && !force) return;
		inviteOpen = false;
		inviteEmail = '';
		inviteRole = 'field';
		inviteError = '';
		inviteFieldErrors = {};
	}

	async function sendInvite() {
		if (inviteSaving) return;
		inviteSaving = true;
		inviteError = '';
		inviteFieldErrors = {};
		try {
			const result = await createTeamInvitation({
				email: inviteEmail,
				role: inviteRole
			});
			await queryClient.invalidateQueries({ queryKey: ['team', 'directory'] });
			if (result.status === 'delivery_failed') {
				toast.warning(
					'Invitation created',
					'Email delivery failed. You can resend it from this person’s page.'
				);
			} else {
				toast.success('Invitation sent.');
			}
			closeInvite(true);
		} catch (error) {
			if (error instanceof TeamInvitationWriteError) {
				inviteError = error.message;
				inviteFieldErrors = error.fieldErrors;
			} else {
				inviteError = error instanceof Error ? error.message : 'The invitation could not be sent.';
			}
		} finally {
			inviteSaving = false;
		}
	}

	function memberName(member: TeamDirectoryMember) {
		return member.display_name ?? member.invitation?.email ?? 'Team member';
	}

	function memberRole(member: TeamDirectoryMember) {
		return member.role === 'admin'
			? 'Administrator'
			: `${member.role[0].toUpperCase()}${member.role.slice(1)}`;
	}

	function roleTone(role: TeamMemberRole): 'warning' | 'informative' | undefined {
		if (role === 'admin') return 'informative';
		return undefined;
	}

	function memberWorkDetails(member: TeamDirectoryMember) {
		return (
			[member.job_title, member.work_phone].filter(Boolean).join(' · ') || 'No work details yet'
		);
	}

	function statusTone(memberStatus: TeamMemberStatus) {
		return memberStatus === 'active'
			? 'success'
			: memberStatus === 'pending'
				? 'warning'
				: 'inactive';
	}

	function statusLabel(memberStatus: TeamMemberStatus) {
		return `${memberStatus[0].toUpperCase()}${memberStatus.slice(1)}`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Team · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="open">
		<div class="team__header">
			<span class="team__page-icon" aria-hidden="true">{@html usersIcon}</span>
			<div class="team__heading">
				<Breadcrumbs
					items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Team' }]}
				/>
				<PageHeader
					icon={usersGroupPageIcon}
					tone="inactive"
					title="Team"
					description="The people who work in your business and their current access."
				>
					{#snippet actions()}
						<Button
							href={resolve('/(app)/settings/team/activity')}
							variant="secondary"
							variation="subtle"
							><span class="team__button-icon" aria-hidden="true">{@html historyIcon}</span>Activity
							log</Button
						>
						<Button onclick={() => (inviteOpen = true)}
							><span class="team__button-icon" aria-hidden="true">{@html userPlusIcon}</span>Invite
							member</Button
						>
					{/snippet}
				</PageHeader>
			</div>
		</div>

		<div class="team__summary" aria-live="polite">
			<span class="team__seat-icon" aria-hidden="true">{@html armchairIcon}</span>
			<div class="team__seat-copy">
				<span class="team__summary-label">Team seats</span>
				{#if teamQuery.isPending}
					<span class="team__summary-loading">Loading seat usage…</span>
				{:else if seats}
					<strong>{seatSummary}</strong>
					{#if !seats.is_unlimited && seats.limit > 0}
						<meter
							class="team__seat-meter"
							min="0"
							max={seats.limit}
							value={Math.min(seats.used, seats.limit)}
							aria-label={seatSummary}>{seatSummary}</meter
						>
					{/if}
				{/if}
			</div>
		</div>

		<section class="team__card" aria-labelledby="team-members-heading">
			<div class="team__card-header">
				<h2 id="team-members-heading">Team members</h2>
				<div class="team__toolbar">
					<SearchInput
						id="team-search"
						bind:value={search}
						placeholder="Search people or invited email"
						ariaLabel="Search team members"
					/>
					<Select
						id="team-status-filter"
						ariaLabel="Filter team members by status"
						prefix="Status"
						value={status}
						onchange={setStatus}
						options={[
							{ value: '', label: 'All statuses' },
							{ value: 'pending', label: 'Pending' },
							{ value: 'active', label: 'Active' },
							{ value: 'deactivated', label: 'Deactivated' }
						]}
					/>
					{#if hasFilters}<Button size="small" variant="tertiary" onclick={clearFilters}
							>Clear</Button
						>{/if}
				</div>
			</div>

			{#if teamQuery.isPending}
				<LoadingSkeleton variant="table" label="Loading team members" rows={5} />
			{:else if teamQuery.isError}
				<ErrorState
					description="Team members could not be loaded. Refresh and try again."
					retry={() => teamQuery.refetch()}
				/>
			{:else if members.length === 0}
				<EmptyState
					icon={usersIcon}
					title={hasFilters ? 'No matching team members' : 'No team members yet'}
					description={hasFilters
						? 'Try a different search term or clear your filters.'
						: 'People you invite will show up here.'}
				/>
			{:else}
				<div class="team__directory">
					<DataTable
						variant="card"
						{columns}
						items={members}
						rowId={(member) => member.user_id}
						caption="Team members"
						onRowActivate={(member) =>
							void goto(
								resolve('/(app)/settings/team/[userId]', {
									userId: member.user_id
								})
							)}
					>
						{#snippet row(member: TeamDirectoryMember)}
							<th scope="row">
								<div class="team__member">
									<Avatar
										id={member.user_id}
										name={memberName(member)}
										src={member.avatar_url}
										size="base"
									/>
									<a
										href={resolve('/(app)/settings/team/[userId]', {
											userId: member.user_id
										})}
										class="team__member-name">{memberName(member)}</a
									>
								</div>
							</th>
							<td class="team__role"
								><Badge
									class={member.role === 'owner' ? 'team__owner-badge' : ''}
									status={roleTone(member.role)}
									dot={false}>{memberRole(member)}</Badge
								></td
							>
							<td class="team__work-details">{memberWorkDetails(member)}</td>
							<td>
								<div class="team__status-cell">
									<StatusBadge status={statusTone(member.status)}
										>{statusLabel(member.status)}</StatusBadge
									>
									{#if member.status === 'pending' && member.invitation?.delivery_failed}
										<StatusBadge status="critical">Delivery failed</StatusBadge>
									{/if}
								</div>
							</td>
							<td><span class="team__chevron" aria-hidden="true">{@html chevronRightIcon}</span></td
							>
						{/snippet}
						{#snippet footer()}
							<ListLoadMore
								hasNextPage={teamQuery.hasNextPage}
								isFetchingNextPage={teamQuery.isFetchingNextPage}
								onLoadMore={() => teamQuery.fetchNextPage()}
							/>
						{/snippet}
					</DataTable>
				</div>
			{/if}
		</section>
	</PageContainer>
</div>

{#if inviteOpen}
	<Dialog open title="Invite member" size="small" onClose={closeInvite}>
		<form
			class="team__invite"
			onsubmit={(event) => {
				event.preventDefault();
				void sendInvite();
			}}
		>
			<p class="team__invite-copy">
				They’ll get an email to join your business. Pending invitations use a seat.
			</p>
			<Input
				id="team-invite-email"
				label="Email address"
				type="email"
				required
				bind:value={inviteEmail}
				invalid={Boolean(inviteFieldErrors.email)}
				errorMessage={inviteFieldErrors.email}
				disabled={inviteSaving}
			/>
			<div class="team__invite-field">
				<label for="team-invite-role"
					>Role<span class="field-required" aria-hidden="true">*</span></label
				>
				<Select
					id="team-invite-role"
					ariaLabel="Role"
					bind:value={inviteRole}
					options={[
						{ value: 'admin', label: 'Administrator' },
						{ value: 'office', label: 'Office' },
						{ value: 'sales', label: 'Sales' },
						{ value: 'field', label: 'Field' },
						{ value: 'finance', label: 'Finance' }
					]}
					disabled={inviteSaving}
				/>
				<p>
					Administrators can manage the Team. Owners are the only people who can make or change an
					Administrator.
				</p>
			</div>
			{#if inviteError}<p class="team__invite-error" role="alert">
					{inviteError}
				</p>{/if}
			<div class="team__invite-actions">
				<Button
					type="button"
					variant="secondary"
					variation="subtle"
					disabled={inviteSaving}
					onclick={() => closeInvite()}>Cancel</Button
				>
				<Button type="submit" loading={inviteSaving} disabled={!inviteEmail.trim()}
					>Send invitation</Button
				>
			</div>
		</form>
	</Dialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.team__header {
		display: flex;
		align-items: center;
		gap: 16px;
		margin-bottom: 24px;
	}
	.team__heading {
		flex: 1;
		min-width: 0;
	}
	.team__heading :global(.breadcrumbs) {
		margin-bottom: 4px;
		font-size: 12px;
	}
	.team__heading :global(.page-header) {
		margin-bottom: 0;
		padding-top: 0;
	}
	.team__page-icon,
	.team__seat-icon {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		border-radius: var(--radius-base);
	}
	.team__page-icon {
		width: 48px;
		height: 48px;
		background: var(--color-quote);
		color: var(--color-white);
	}
	.team__page-icon :global(svg) {
		width: 24px;
		height: 24px;
	}
	.team__seat-icon {
		width: 36px;
		height: 36px;
		background: var(--color-quote--surface);
		color: var(--color-quote);
	}
	.team__seat-icon :global(svg) {
		width: 18px;
		height: 18px;
	}
	.team__button-icon,
	.team__chevron {
		display: inline-flex;
	}
	.team__button-icon :global(svg),
	.team__chevron :global(svg) {
		width: 16px;
		height: 16px;
	}
	.team__chevron {
		color: var(--color-icon--secondary);
	}
	.team__summary {
		display: flex;
		align-items: center;
		gap: 14px;
		margin-bottom: 24px;
		padding: 16px 20px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		color: var(--color-text);
	}
	.team__seat-copy {
		display: grid;
		gap: 3px;
	}
	.team__seat-copy strong {
		color: var(--color-heading);
		font-size: 15px;
	}
	.team__summary-label,
	.team__summary-loading {
		color: var(--color-text--secondary);
		font-size: 12px;
	}
	.team__summary-label {
		font-weight: 600;
	}
	.team__seat-meter {
		appearance: none;
		width: 240px;
		height: 8px;
		margin-top: 5px;
		border: 0;
		border-radius: var(--radius-large);
		background: var(--color-surface--active);
	}
	.team__seat-meter::-webkit-meter-bar {
		background: var(--color-surface--active);
		border: 0;
		border-radius: var(--radius-large);
	}
	.team__seat-meter::-webkit-meter-optimum-value {
		background: var(--color-quote);
		border-radius: var(--radius-large);
	}
	.team__seat-meter::-moz-meter-bar {
		background: var(--color-quote);
		border-radius: var(--radius-large);
	}
	.team__card {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.team__card-header {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: center;
		gap: 16px;
		padding: 18px 24px;
	}
	.team__card-header h2 {
		color: var(--color-heading);
		font-size: 16px;
		font-weight: 700;
	}
	.team__toolbar {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.team__toolbar :global(.search-input) {
		width: 300px;
		flex: 0 0 300px;
	}
	.team__toolbar :global(.select) {
		width: 200px;
		flex: 0 0 200px;
	}
	.team__directory {
		--data-table-min-width: 900px;
	}
	.team__member :global(.avatar) {
		--avatar-bg: var(--color-surface--active);
		--avatar-fg: var(--color-text);
	}
	.team__role :global(.team__owner-badge) {
		color: var(--color-white);
		background: var(--color-base-blue--900);
	}
	:global([data-theme='dark']) .team__role :global(.team__owner-badge) {
		background: var(--color-surface--background);
	}
	.team__work-details {
		color: var(--color-text--secondary);
		font-size: 13px;
	}

	.team__member {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.team__status-cell {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	.team__member-name {
		color: var(--color-heading);
		font-weight: 700;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}

	.team__invite {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.team__invite-copy,
	.team__invite-field p {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.team__invite-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
	}

	.team__invite-field > label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.team__invite-error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.team__invite-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	@media (max-width: 767px) {
		.team__summary {
			margin: var(--space-base) 0;
		}
	}

	@media (max-width: 489px) {
		.team__directory :global(th:nth-child(2)),
		.team__directory :global(th:nth-child(3)),
		.team__directory :global(.team__role),
		.team__directory :global(.team__work-details) {
			display: none;
		}
	}
</style>
