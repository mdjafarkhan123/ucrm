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
	import {
		cancelTeamInvitation,
		fetchTeamMember,
		replaceTeamInvitationEmail,
		resendTeamInvitation,
		saveTeamMemberProfile,
		teamDirectoryKey,
		teamMemberKey,
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
	const isDirty = $derived(Boolean(saved && draft && !sameDraft(draft, draftOf(saved))));

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
		saveError = '';
		stale = false;
	}

	function cancelEdit() {
		draft = null;
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
		try {
			await saveTeamMemberProfile(userId, draft);
			draft = null;
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
										<dt>Joined</dt>
										<dd>{formatDate(member.created_at)}</dd>
									</div>
								</dl>
							{/if}
						</SectionBlock>

						<TeamAccessEditor {userId} />
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
							{:else}
								<p class="team-member-detail__rail-copy">
									This person can sign in and use their current access.
								</p>
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
