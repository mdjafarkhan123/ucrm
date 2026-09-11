<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import TeamAccessEditor from '$lib/components/settings/TeamAccessEditor.svelte';
	import MemberAvailabilityEditor from '$lib/components/settings/MemberAvailabilityEditor.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import type { HttpError } from '$lib/http-error';
	import {
		cancelTeamInvitation,
		deactivateTeamMember,
		fetchIncompleteWork,
		fetchTeamDirectory,
		fetchTeamMember,
		removeTeamMember,
		replaceTeamInvitationEmail,
		resendTeamInvitation,
		restoreTeamMember,
		saveTeamMemberCostRate,
		saveTeamMemberProfile,
		teamDirectoryKey,
		teamMemberIncompleteWorkKey,
		teamMemberKey,
		teamSeatsKey,
		type IncompleteWork,
		type TeamMemberDetail,
		type TeamMemberProfileDraft,
		TeamInvitationWriteError,
		TeamWriteError
	} from '$lib/team/api';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const userId = $derived(page.params.userId ?? '');
	const actorUserId = $derived(page.data.user?.id ?? '');
	const viewerRole = $derived(page.data.organization?.role ?? null);
	const memberQuery = createQuery(() => ({
		queryKey: teamMemberKey(actorUserId, userId),
		queryFn: () => fetchTeamMember(userId),
		enabled: Boolean(actorUserId && userId),
		staleTime: 30_000
	}));

	let draft = $state<TeamMemberProfileDraft | null>(null);
	let saving = $state(false);
	let saveError = $state('');
	let stale = $state(false);

	let resendOpen = $state(false);
	let resendSaving = $state(false);
	let resendError = $state('');

	let cancelOpen = $state(false);
	let cancelSaving = $state(false);
	let cancelError = $state('');

	let changeEmailOpen = $state(false);
	let changeEmailValue = $state('');
	let changeEmailSaving = $state(false);
	let changeEmailError = $state('');
	let changeEmailFieldErrors = $state<Record<string, string>>({});

	let deactivateOpen = $state(false);
	let deactivateSaving = $state(false);
	let deactivateError = $state('');

	let restoreOpen = $state(false);
	let restoreSaving = $state(false);
	let restoreError = $state('');

	let removeOpen = $state(false);
	let removeSaving = $state(false);
	let removeError = $state('');
	let removeTypedName = $state('');

	const incompleteWorkQuery = createQuery(() => ({
		queryKey: teamMemberIncompleteWorkKey(actorUserId, userId),
		queryFn: () => fetchIncompleteWork(userId),
		enabled: deactivateOpen && Boolean(actorUserId && userId),
		staleTime: 30_000
	}));
	const incompleteWork = $derived<IncompleteWork | undefined>(incompleteWorkQuery.data);
	const hasIncompleteWork = $derived(
		Boolean(
			incompleteWork &&
			(incompleteWork.assessments_total ||
				incompleteWork.visits_total ||
				incompleteWork.tasks_total)
		)
	);

	const seatsQuery = createQuery(() => ({
		queryKey: teamSeatsKey(actorUserId),
		queryFn: () => fetchTeamDirectory({ search: '', status: '' }),
		enabled: restoreOpen && Boolean(actorUserId),
		staleTime: 30_000
	}));
	const seats = $derived(seatsQuery.data?.seats);

	function prefetchIncompleteWork() {
		if (!actorUserId || !userId) return;
		void queryClient.prefetchQuery({
			queryKey: teamMemberIncompleteWorkKey(actorUserId, userId),
			queryFn: () => fetchIncompleteWork(userId),
			staleTime: 30_000
		});
	}

	function prefetchSeats() {
		if (!actorUserId) return;
		void queryClient.prefetchQuery({
			queryKey: teamSeatsKey(actorUserId),
			queryFn: () => fetchTeamDirectory({ search: '', status: '' }),
			staleTime: 30_000
		});
	}

	// Member details and Role & access are an admin's view of someone else's record; Availability is the one
	// section a member owns for themselves, and its own route already enforces that (self, or an owner or
	// administrator). So a member refused the admin-only member fetch for their own id still gets that one
	// section, instead of the whole page reading as broken.
	const viewingOwnRecordWithoutAdminAccess = $derived(
		Boolean(actorUserId) &&
			userId === actorUserId &&
			(memberQuery.error as HttpError | null)?.status === 403
	);

	const saved = $derived(memberQuery.data);
	const member = $derived.by(() => {
		if (!saved) return undefined;
		return {
			...saved,
			display_name: draft?.full_name || saved.display_name,
			work_phone: draft?.work_phone ?? saved.work_phone,
			job_title: draft?.job_title ?? saved.job_title,
			schedule_color: draft?.schedule_color ?? saved.schedule_color
		} satisfies TeamMemberDetail;
	});
	const isEditing = $derived(draft !== null);

	// Owner-only, and only once the role editor's own "demote an administrator first" rule is already
	// satisfied -- remove_team_member enforces both server-side; this just avoids surfacing a button that
	// would only ever answer with a refusal.
	const canRemove = $derived(
		Boolean(
			member &&
			viewerRole === 'owner' &&
			member.status === 'deactivated' &&
			member.role !== 'admin' &&
			userId !== actorUserId
		)
	);

	// The hourly cost is edited beside the profile and saved by the same bar, but it is written on its own
	// route: a name and a wage are not the same kind of fact, and only the wage lives behind a separate,
	// permission-checked table. Held as the text in the box so a half-typed "12." is not read as a number.
	let costRate = $state('');

	function costRateOf(source: TeamMemberDetail) {
		return source.cost_per_hour_minor === null ? '' : (source.cost_per_hour_minor / 100).toFixed(2);
	}

	// Empty means "not told yet", which the command stores as null. Anything else has to be a real amount:
	// a typo saved as zero would quietly report this person's hours as free.
	function costRateToMinor(): number | null | 'invalid' {
		const text = costRate.trim();
		if (!text) return null;
		const value = Number(text);
		if (!Number.isFinite(value) || value < 0) return 'invalid';
		return Math.round(value * 100);
	}

	const isDirty = $derived(
		Boolean(saved && draft && (!sameDraft(draft, draftOf(saved)) || costRate !== costRateOf(saved)))
	);

	function draftOf(source: TeamMemberDetail): TeamMemberProfileDraft {
		return {
			full_name: source.display_name ?? '',
			work_phone: source.work_phone ?? '',
			job_title: source.job_title ?? '',
			schedule_color: source.schedule_color ?? '',
			expected_profile_revision: source.profile_revision
		};
	}

	function sameDraft(a: TeamMemberProfileDraft, b: TeamMemberProfileDraft) {
		return (
			a.full_name.trim() === b.full_name.trim() &&
			a.work_phone.trim() === b.work_phone.trim() &&
			a.job_title.trim() === b.job_title.trim() &&
			a.schedule_color.toUpperCase() === b.schedule_color.toUpperCase()
		);
	}

	function displayName(source: TeamMemberDetail) {
		return source.display_name ?? source.invitation?.email ?? 'Team member';
	}

	function roleLabel(role: TeamMemberDetail['role']) {
		return role === 'admin' ? 'Administrator' : `${role[0].toUpperCase()}${role.slice(1)}`;
	}

	function statusTone(status: TeamMemberDetail['status']) {
		return status === 'active' ? 'success' : status === 'pending' ? 'warning' : 'inactive';
	}

	function statusLabel(status: TeamMemberDetail['status']) {
		return `${status[0].toUpperCase()}${status.slice(1)}`;
	}

	function formatDate(value: string | null) {
		if (!value) return 'Not recorded';
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
	}

	function openEdit() {
		if (!saved) return;
		draft = draftOf(saved);
		costRate = costRateOf(saved);
		saveError = '';
		stale = false;
	}

	function cancelEdit() {
		draft = null;
		costRate = '';
		saveError = '';
		stale = false;
	}

	async function reloadLatest() {
		await queryClient.fetchQuery({
			queryKey: teamMemberKey(actorUserId, userId),
			queryFn: () => fetchTeamMember(userId),
			staleTime: 0
		});
		saveError = '';
		stale = false;
	}

	async function saveDraft() {
		if (!draft || saving || !isDirty) return;
		saving = true;
		saveError = '';
		stale = false;
		const rate = costRateToMinor();
		if (rate === 'invalid') {
			saveError = 'Enter the hourly cost as an amount, like 24.50, or leave it blank.';
			saving = false;
			return;
		}
		try {
			if (!sameDraft(draft, draftOf(saved!))) await saveTeamMemberProfile(userId, draft);
			if (rate !== (saved?.cost_per_hour_minor ?? null)) {
				await saveTeamMemberCostRate(userId, rate);
			}
			draft = null;
			costRate = '';
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: teamMemberKey(actorUserId, userId) }),
				queryClient.invalidateQueries({ queryKey: ['team', 'directory'] })
			]);
		} catch (error) {
			stale = error instanceof TeamWriteError && error.stale;
			saveError =
				error instanceof Error ? error.message : 'Those member details could not be saved.';
		} finally {
			saving = false;
		}
	}

	function openResend() {
		resendError = '';
		resendOpen = true;
	}

	function closeResend() {
		if (resendSaving) return;
		resendOpen = false;
		resendError = '';
	}

	async function confirmResend() {
		if (!member?.invitation || resendSaving) return;
		resendSaving = true;
		resendError = '';
		try {
			const result = await resendTeamInvitation(member.invitation.id);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: teamMemberKey(actorUserId, userId) }),
				queryClient.invalidateQueries({ queryKey: ['team', 'directory'] })
			]);
			resendOpen = false;
			if (result.status === 'delivery_failed') {
				toast.warning('Invitation resent', 'Email delivery failed. You can try resending again.');
			} else {
				toast.success('Invitation resent.');
			}
		} catch (error) {
			resendError = error instanceof Error ? error.message : 'The invitation could not be resent.';
		} finally {
			resendSaving = false;
		}
	}

	function openCancel() {
		cancelError = '';
		cancelOpen = true;
	}

	function closeCancel() {
		if (cancelSaving) return;
		cancelOpen = false;
		cancelError = '';
	}

	async function confirmCancel() {
		if (!member?.invitation || cancelSaving) return;
		cancelSaving = true;
		cancelError = '';
		try {
			await cancelTeamInvitation(member.invitation.id);
			queryClient.removeQueries({ queryKey: teamMemberKey(actorUserId, userId) });
			await queryClient.invalidateQueries({ queryKey: ['team', 'directory'] });
			toast.success('Invitation cancelled.');
			await goto(resolve('/(app)/settings/team'));
		} catch (error) {
			cancelError =
				error instanceof Error ? error.message : 'The invitation could not be cancelled.';
		} finally {
			cancelSaving = false;
		}
	}

	function openChangeEmail() {
		changeEmailValue = member?.invitation?.email ?? '';
		changeEmailError = '';
		changeEmailFieldErrors = {};
		changeEmailOpen = true;
	}

	function closeChangeEmail() {
		if (changeEmailSaving) return;
		changeEmailOpen = false;
		changeEmailValue = '';
		changeEmailError = '';
		changeEmailFieldErrors = {};
	}

	async function submitChangeEmail() {
		if (!member?.invitation || changeEmailSaving) return;
		changeEmailSaving = true;
		changeEmailError = '';
		changeEmailFieldErrors = {};
		try {
			const result = await replaceTeamInvitationEmail(member.invitation.id, changeEmailValue);
			queryClient.removeQueries({ queryKey: teamMemberKey(actorUserId, userId) });
			await queryClient.invalidateQueries({ queryKey: ['team', 'directory'] });
			if (result.status === 'delivery_failed') {
				toast.warning(
					'Email changed',
					`Delivery failed sending to ${changeEmailValue}. Resend it from the Team list.`
				);
			} else {
				toast.success(`A new invitation was sent to ${changeEmailValue}.`);
			}
			await goto(resolve('/(app)/settings/team'));
		} catch (error) {
			if (error instanceof TeamInvitationWriteError) {
				changeEmailError = error.message;
				changeEmailFieldErrors = error.fieldErrors;
			} else {
				changeEmailError =
					error instanceof Error ? error.message : 'The email could not be changed.';
			}
		} finally {
			changeEmailSaving = false;
		}
	}

	function openDeactivate() {
		deactivateError = '';
		deactivateOpen = true;
	}

	function closeDeactivate() {
		if (deactivateSaving) return;
		deactivateOpen = false;
		deactivateError = '';
	}

	async function confirmDeactivate() {
		if (!member || deactivateSaving) return;
		deactivateSaving = true;
		deactivateError = '';
		try {
			await deactivateTeamMember(userId);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: teamMemberKey(actorUserId, userId) }),
				queryClient.invalidateQueries({ queryKey: ['team', 'directory'] })
			]);
			deactivateOpen = false;
			toast.success(`${displayName(member)} was deactivated.`);
		} catch (error) {
			deactivateError =
				error instanceof Error ? error.message : 'That person could not be deactivated.';
		} finally {
			deactivateSaving = false;
		}
	}

	function openRestore() {
		restoreError = '';
		restoreOpen = true;
	}

	function closeRestore() {
		if (restoreSaving) return;
		restoreOpen = false;
		restoreError = '';
	}

	async function confirmRestore() {
		if (!member || restoreSaving) return;
		restoreSaving = true;
		restoreError = '';
		try {
			await restoreTeamMember(userId);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: teamMemberKey(actorUserId, userId) }),
				queryClient.invalidateQueries({ queryKey: ['team', 'directory'] })
			]);
			restoreOpen = false;
			toast.success(`${displayName(member)} was restored.`);
		} catch (error) {
			restoreError = error instanceof Error ? error.message : 'That person could not be restored.';
		} finally {
			restoreSaving = false;
		}
	}

	function openRemove() {
		removeError = '';
		removeTypedName = '';
		removeOpen = true;
	}

	function closeRemove() {
		if (removeSaving) return;
		removeOpen = false;
		removeError = '';
		removeTypedName = '';
	}

	async function confirmRemove() {
		if (!member || removeSaving || removeTypedName.trim() !== displayName(member)) return;
		removeSaving = true;
		removeError = '';
		try {
			await removeTeamMember(userId);
			queryClient.removeQueries({ queryKey: teamMemberKey(actorUserId, userId) });
			await queryClient.invalidateQueries({ queryKey: ['team', 'directory'] });
			toast.success(`${displayName(member)} was permanently removed.`);
			await goto(resolve('/(app)/settings/team'));
		} catch (error) {
			removeError =
				error instanceof Error ? error.message : 'That person could not be permanently removed.';
		} finally {
			removeSaving = false;
		}
	}
</script>

<svelte:head>
	<title>{member ? `${displayName(member)} · Team` : 'Team member'} · Contractor CRM</title>
</svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<Breadcrumbs
			items={[
				{ label: 'Team', href: resolve('/(app)/settings/team') },
				{ label: member ? displayName(member) : 'Team member' }
			]}
		/>

		{#if memberQuery.isPending}
			<LoadingSkeleton variant="card" label="Loading team member" />
		{:else if viewingOwnRecordWithoutAdminAccess}
			<PageHeader
				eyebrow="Team & access"
				title="Your availability"
				description="When you work, and time off you've booked."
			/>
			<MemberAvailabilityEditor {userId} />
		{:else if memberQuery.isError}
			<ErrorState
				description="That team member could not be loaded. Refresh and try again."
				retry={() => memberQuery.refetch()}
			/>
		{:else if member}
			<PageHeader
				eyebrow="Team & access"
				title={displayName(member)}
				description="Business details and the access this person has in your CRM."
			/>

			<div class="team-member-detail">
				<RecordDetailLayout
					editing={isEditing}
					dirty={isDirty}
					{saving}
					error={saveError}
					onSave={() => void saveDraft()}
					onCancel={cancelEdit}
				>
					{#snippet main()}
						<SectionBlock title="Member details" icon={userIcon} level={2} form={isEditing}>
							{#snippet actions()}
								{#if !isEditing}
									<PencilButton onclick={openEdit} label={`Edit ${displayName(member)}`} />
								{/if}
							{/snippet}

							{#if stale}
								<div class="team-member-detail__conflict" role="alert">
									<p>Someone else changed this person’s details while you were editing.</p>
									<button type="button" onclick={() => void reloadLatest()}
										>Reload latest details</button
									>
								</div>
							{/if}

							{#if isEditing && draft}
								<div class="team-member-detail__form-grid">
									<Input id="team-member-name" label="Display name" bind:value={draft.full_name} />
									<Input
										id="team-member-phone"
										label="Work phone"
										type="tel"
										bind:value={draft.work_phone}
									/>
									<Input id="team-member-title" label="Job title" bind:value={draft.job_title} />
									<Input
										id="team-member-cost-rate"
										label="Hourly cost"
										inputmode="decimal"
										placeholder="e.g. 24.50 — leave blank if not set"
										bind:value={costRate}
									/>
									<div class="team-member-detail__color-field">
										<label for="team-member-color">Scheduling color</label>
										<input
											id="team-member-color"
											type="color"
											value={draft.schedule_color || '#4F7C1D'}
											oninput={(event) => (draft!.schedule_color = event.currentTarget.value)}
										/>
										<span>{draft.schedule_color || 'Not set'}</span>
									</div>
								</div>
								<p class="team-member-detail__hint">
									Hourly cost is what this person costs the business — wage, benefits and taxes —
									and is only used for job costing. Changing it applies to hours recorded from now
									on; hours already recorded keep the rate they were recorded with.
								</p>
							{:else}
								<div class="team-member-detail__identity">
									<Avatar
										id={member.user_id}
										name={displayName(member)}
										src={member.avatar_url}
										size="medium"
									/>
									<div>
										<strong>{displayName(member)}</strong>
										<p>{member.job_title ?? 'No job title yet'}</p>
									</div>
								</div>
								<dl class="team-member-detail__facts">
									<div>
										<dt>Work phone</dt>
										<dd>{member.work_phone ?? 'Not recorded'}</dd>
									</div>
									<div>
										<dt>Scheduling color</dt>
										<dd>{member.schedule_color ?? 'Not set'}</dd>
									</div>
									<div>
										<dt>Hourly cost</dt>
										<dd>
											{member.cost_per_hour_minor === null
												? 'Not set'
												: `${(member.cost_per_hour_minor / 100).toFixed(2)} per hour`}
										</dd>
									</div>
									<div>
										<dt>Joined</dt>
										<dd>{formatDate(member.created_at)}</dd>
									</div>
								</dl>
							{/if}
						</SectionBlock>

						<TeamAccessEditor {userId} />

						<MemberAvailabilityEditor {userId} />
					{/snippet}

					{#snippet rail()}
						<RailCard title="Current status" icon={briefcaseIcon}>
							<StatusBadge status={statusTone(member.status)}
								>{statusLabel(member.status)}</StatusBadge
							>
							{#if member.status === 'pending' && member.invitation}
								{#if member.invitation.delivery_failed}
									<div class="team-member-detail__delivery-failed">
										<StatusBadge status="critical">Delivery failed</StatusBadge>
									</div>
								{/if}
								<p class="team-member-detail__rail-copy">Invited: {member.invitation.email}</p>
								<p class="team-member-detail__rail-copy">
									Invitation expires {formatDate(member.invitation.expires_at)}.
								</p>
								<div class="team-member-detail__invitation-actions">
									<Button
										type="button"
										variant="secondary"
										variation="subtle"
										size="small"
										onclick={openResend}>Resend invitation</Button
									>
									<Button
										type="button"
										variant="secondary"
										variation="subtle"
										size="small"
										onclick={openChangeEmail}>Change email</Button
									>
									<Button
										type="button"
										variant="secondary"
										variation="destructive"
										size="small"
										onclick={openCancel}>Cancel invitation</Button
									>
								</div>
							{:else if member.status === 'deactivated'}
								<p class="team-member-detail__rail-copy">
									Deactivated {formatDate(member.deactivated_at)}.
								</p>
								<div class="team-member-detail__invitation-actions">
									<Button
										type="button"
										variant="secondary"
										variation="work"
										size="small"
										onhover={prefetchSeats}
										onclick={openRestore}>Restore</Button
									>
									{#if canRemove}
										<Button
											type="button"
											variant="secondary"
											variation="destructive"
											size="small"
											onclick={openRemove}>Permanently remove</Button
										>
									{/if}
								</div>
							{:else}
								<p class="team-member-detail__rail-copy">
									This person can sign in and use their current access.
								</p>
								<div class="team-member-detail__invitation-actions">
									<Button
										type="button"
										variant="secondary"
										variation="destructive"
										size="small"
										onhover={prefetchIncompleteWork}
										onclick={openDeactivate}>Deactivate</Button
									>
								</div>
							{/if}
						</RailCard>
					{/snippet}
				</RecordDetailLayout>
			</div>
		{/if}
	</PageContainer>
</div>

{#if member?.invitation}
	<ConfirmDialog
		open={resendOpen}
		title="Resend invitation?"
		confirmLabel="Resend invitation"
		loading={resendSaving}
		onConfirm={() => void confirmResend()}
		onClose={closeResend}
	>
		<p>
			We’ll send a new link to <strong>{member?.invitation?.email}</strong> and the old link will stop
			working.
		</p>
		{#if resendError}<p class="team-member-detail__dialog-error" role="alert">{resendError}</p>{/if}
	</ConfirmDialog>

	<ConfirmDialog
		open={cancelOpen}
		title="Cancel this invitation?"
		tone="critical"
		destructive
		confirmLabel="Cancel invitation"
		cancelLabel="Keep invitation"
		loading={cancelSaving}
		onConfirm={() => void confirmCancel()}
		onClose={closeCancel}
	>
		<p>
			<strong>{member?.invitation?.email}</strong> won’t be able to join with this link. Their seat is
			freed up.
		</p>
		{#if cancelError}<p class="team-member-detail__dialog-error" role="alert">{cancelError}</p>{/if}
	</ConfirmDialog>

	{#if changeEmailOpen}
		<Dialog open title="Change invitation email" size="small" onClose={closeChangeEmail}>
			<form
				class="team-member-detail__change-email"
				onsubmit={(event) => {
					event.preventDefault();
					void submitChangeEmail();
				}}
			>
				<p class="team-member-detail__change-email-copy">
					We’ll cancel the invitation to {member.invitation.email} and send a fresh one to the new address.
				</p>
				<Input
					id="team-member-change-email"
					label="New email address"
					type="email"
					required
					bind:value={changeEmailValue}
					invalid={Boolean(changeEmailFieldErrors.email)}
					errorMessage={changeEmailFieldErrors.email}
					disabled={changeEmailSaving}
				/>
				{#if changeEmailError}<p class="team-member-detail__dialog-error" role="alert">
						{changeEmailError}
					</p>{/if}
				<div class="team-member-detail__change-email-actions">
					<Button
						type="button"
						variant="secondary"
						variation="subtle"
						disabled={changeEmailSaving}
						onclick={closeChangeEmail}>Cancel</Button
					>
					<Button type="submit" loading={changeEmailSaving} disabled={!changeEmailValue.trim()}
						>Send new invitation</Button
					>
				</div>
			</form>
		</Dialog>
	{/if}
{/if}

{#if member}
	<ConfirmDialog
		open={deactivateOpen}
		title={`Deactivate ${displayName(member)}?`}
		tone="critical"
		destructive
		confirmLabel="Deactivate"
		loading={deactivateSaving}
		onConfirm={() => void confirmDeactivate()}
		onClose={closeDeactivate}
	>
		<p>
			<strong>{displayName(member)}</strong> won’t be able to sign in. Any work assigned to them below
			will be unassigned so someone else can pick it up.
		</p>
		{#if incompleteWorkQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading assigned work" />
		{:else if hasIncompleteWork && incompleteWork}
			<ul class="team-member-detail__incomplete-work">
				{#if incompleteWork.assessments_total}
					<li>
						{incompleteWork.assessments_total}
						{incompleteWork.assessments_total === 1 ? 'assessment' : 'assessments'}
					</li>
				{/if}
				{#if incompleteWork.visits_total}
					<li>
						{incompleteWork.visits_total}
						{incompleteWork.visits_total === 1 ? 'visit' : 'visits'}
					</li>
				{/if}
				{#if incompleteWork.tasks_total}
					<li>
						{incompleteWork.tasks_total}
						{incompleteWork.tasks_total === 1 ? 'task' : 'tasks'}
					</li>
				{/if}
			</ul>
		{/if}
		{#if deactivateError}<p class="team-member-detail__dialog-error" role="alert">
				{deactivateError}
			</p>{/if}
	</ConfirmDialog>

	<ConfirmDialog
		open={restoreOpen}
		title={`Restore ${displayName(member)}?`}
		confirmLabel="Restore"
		loading={restoreSaving}
		onConfirm={() => void confirmRestore()}
		onClose={closeRestore}
	>
		<p>
			<strong>{displayName(member)}</strong> will be able to sign in and use their access again.
		</p>
		{#if seatsQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading seat usage" />
		{:else if seats}
			<p class="team-member-detail__rail-copy">
				{seats.used} of {seats.is_unlimited ? 'unlimited' : seats.limit} seats used.
			</p>
		{/if}
		{#if restoreError}<p class="team-member-detail__dialog-error" role="alert">
				{restoreError}
			</p>{/if}
	</ConfirmDialog>

	{#if removeOpen}
		<Dialog
			open
			title={`Permanently remove ${displayName(member)}?`}
			size="small"
			onClose={closeRemove}
		>
			<form
				class="team-member-detail__change-email"
				onsubmit={(event) => {
					event.preventDefault();
					void confirmRemove();
				}}
			>
				<p class="team-member-detail__change-email-copy">
					This deletes their sign-in and personal contact details for good and cannot be undone.
					Their name stays on the work, invoices and messages they already touched.
				</p>
				<Input
					id="team-member-remove-confirm"
					label={`Type "${displayName(member)}" to confirm`}
					bind:value={removeTypedName}
					disabled={removeSaving}
				/>
				{#if removeError}<p class="team-member-detail__dialog-error" role="alert">
						{removeError}
					</p>{/if}
				<div class="team-member-detail__change-email-actions">
					<Button
						type="button"
						variant="secondary"
						variation="subtle"
						disabled={removeSaving}
						onclick={closeRemove}>Cancel</Button
					>
					<Button
						type="submit"
						variation="destructive"
						loading={removeSaving}
						disabled={removeTypedName.trim() !== displayName(member)}>Permanently remove</Button
					>
				</div>
			</form>
		</Dialog>
	{/if}
{/if}

<style lang="scss">
	.team-member-detail :global(.team-member-detail__identity) {
		display: flex;
		align-items: center;
		gap: var(--space-base);
	}
	.team-member-detail :global(.team-member-detail__identity strong) {
		color: var(--color-heading);
	}
	.team-member-detail :global(.team-member-detail__identity p),
	.team-member-detail :global(.team-member-detail__rail-copy) {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
	}
	.team-member-detail :global(.team-member-detail__delivery-failed) {
		margin-top: var(--space-small);
	}
	.team-member-detail :global(.team-member-detail__invitation-actions) {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		margin-top: var(--space-base);
	}
	.team-member-detail :global(.team-member-detail__facts) {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.team-member-detail :global(.team-member-detail__facts dt) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.team-member-detail :global(.team-member-detail__facts dd) {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text);
		font-weight: 600;
	}
	.team-member-detail :global(.team-member-detail__form-grid) {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.team-member-detail :global(.team-member-detail__hint) {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.team-member-detail :global(.team-member-detail__color-field) {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-heading);
		font-weight: 600;
	}
	.team-member-detail :global(.team-member-detail__color-field input) {
		width: var(--space-largest);
		height: var(--space-largest);
		padding: var(--space-smallest);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.team-member-detail :global(.team-member-detail__color-field input:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.team-member-detail :global(.team-member-detail__color-field span) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.team-member-detail :global(.team-member-detail__conflict) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.team-member-detail :global(.team-member-detail__conflict p) {
		margin: 0;
	}
	.team-member-detail :global(.team-member-detail__conflict button) {
		color: inherit;
		font: inherit;
		font-weight: 700;
		text-decoration: underline;
	}
	.team-member-detail :global(.team-member-detail__conflict button:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	.team-member-detail__change-email {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.team-member-detail__change-email-copy {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.team-member-detail__change-email-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	.team-member-detail__dialog-error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.team-member-detail__incomplete-work {
		margin: var(--space-small) 0 0;
		padding-left: var(--space-base);
		color: var(--color-heading);
		font-weight: 600;
	}

	@media (max-width: 767px) {
		.team-member-detail :global(.team-member-detail__facts),
		.team-member-detail :global(.team-member-detail__form-grid) {
			grid-template-columns: 1fr;
		}
		.team-member-detail :global(.team-member-detail__conflict) {
			align-items: flex-start;
			flex-direction: column;
		}
	}
</style>
