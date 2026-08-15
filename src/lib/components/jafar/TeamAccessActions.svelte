<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';

	type TeamMember = {
		user_id: string;
		role: string;
		created_at: string;
		full_name: string | null;
		email: string | null;
		permission_overrides: { permission_key: string; override_state: string }[];
	};
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};
	type ProfileCorrectionInput = {
		full_name: string | null;
		email: string | null;
		reason: string;
		idempotency_key: string;
	};
	type AdministratorRecoveryInput = {
		new_email: string;
		evidence_summary: string;
		reason: string;
		idempotency_key: string;
	};

	class TeamActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'This action could not be completed.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let { organizationId, members }: { organizationId: string; members: TeamMember[] } = $props();

	const queryClient = useQueryClient();
	const isAdministrator = (role: string) => role === 'owner' || role === 'admin';
	const ROLE_LABELS: Record<string, string> = {
		owner: 'Owner',
		admin: 'Admin',
		office: 'Office',
		sales: 'Sales',
		field: 'Field',
		finance: 'Finance'
	};

	function permissionLabel(permissionKey: string) {
		return permissionKey
			.replace(/[._]/g, ' ')
			.replace(/\b\w/g, (letter) => letter.toUpperCase());
	}

	function formatDateTime(value: string | null) {
		if (!value) return 'Not recorded';
		return new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
	}

	function invalidateOrganization() {
		void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations', organizationId] });
		void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
	}

	// ---------------------------------------------------------------------------
	// Profile correction (name any role; email non-admin only)
	// ---------------------------------------------------------------------------

	let correctionMember = $state<TeamMember | null>(null);
	let correctionName = $state('');
	let correctionEmail = $state('');
	let correctionReason = $state('');
	let correctionIdempotencyKey = $state('');
	let correctionFieldErrors = $state<Record<string, string>>({});
	let correctionFeedback = $state('');

	function openCorrection(member: TeamMember) {
		correctionMember = member;
		correctionName = member.full_name ?? '';
		correctionEmail = member.email ?? '';
		correctionReason = '';
		correctionIdempotencyKey = crypto.randomUUID();
		correctionFieldErrors = {};
		correctionFeedback = '';
	}

	function closeCorrection() {
		if (!correctionMutation.isPending) correctionMember = null;
	}

	const correctionMutation = createMutation<MutationResponse, TeamActionError, ProfileCorrectionInput>(
		() => ({
			mutationFn: async (input) => {
				const response = await fetch(
					`/api/jafar/organizations/${organizationId}/team/${correctionMember?.user_id}`,
					{
						method: 'PATCH',
						headers: { 'content-type': 'application/json' },
						body: JSON.stringify(input)
					}
				);
				const result = (await response.json()) as MutationResponse;
				if (!response.ok) throw new TeamActionError(result);
				return result;
			},
			onMutate: () => {
				correctionFieldErrors = {};
			},
			onError: (error) => {
				correctionFieldErrors = error.fieldErrors;
				correctionFeedback = error.message;
			},
			onSuccess: () => {
				correctionMember = null;
				invalidateOrganization();
			}
		})
	);

	function submitCorrection(event: SubmitEvent) {
		event.preventDefault();
		if (!correctionMember) return;
		const errors: Record<string, string> = {};
		if (!correctionReason.trim()) errors.reason = 'Enter a correction reason.';
		correctionFieldErrors = errors;
		if (Object.keys(errors).length > 0) return;

		const canEditEmail = !isAdministrator(correctionMember.role);
		correctionMutation.mutate({
			full_name: correctionName.trim() || null,
			email: canEditEmail ? correctionEmail.trim() || null : null,
			reason: correctionReason.trim(),
			idempotency_key: correctionIdempotencyKey
		});
	}

	// ---------------------------------------------------------------------------
	// Administrator email recovery (owner/admin only, step-up enforced)
	// ---------------------------------------------------------------------------

	let recoveryMember = $state<TeamMember | null>(null);
	let recoveryEmail = $state('');
	let recoveryEvidence = $state('');
	let recoveryReason = $state('');
	let recoveryIdempotencyKey = $state('');
	let recoveryFieldErrors = $state<Record<string, string>>({});
	let recoveryFeedback = $state('');
	let recoveryReconfirmOpen = $state(false);
	let pendingRecoveryInput = $state<AdministratorRecoveryInput | null>(null);

	function openRecovery(member: TeamMember) {
		recoveryMember = member;
		recoveryEmail = '';
		recoveryEvidence = '';
		recoveryReason = '';
		recoveryIdempotencyKey = crypto.randomUUID();
		recoveryFieldErrors = {};
		recoveryFeedback = '';
	}

	function closeRecovery() {
		if (!recoveryMutation.isPending) recoveryMember = null;
	}

	const recoveryMutation = createMutation<
		MutationResponse,
		TeamActionError,
		AdministratorRecoveryInput
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/team/${recoveryMember?.user_id}/administrator-recovery`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(input)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new TeamActionError(result);
			return result;
		},
		onMutate: () => {
			recoveryFieldErrors = {};
			recoveryFeedback = '';
		},
		onError: (error, input) => {
			if (error.stepUpRequired) {
				pendingRecoveryInput = input;
				recoveryReconfirmOpen = true;
				return;
			}
			recoveryFieldErrors = error.fieldErrors;
			recoveryFeedback = error.message;
		},
		onSuccess: () => {
			recoveryMember = null;
			pendingRecoveryInput = null;
			invalidateOrganization();
		}
	}));

	function submitRecovery(event: SubmitEvent) {
		event.preventDefault();
		if (!recoveryMember) return;
		const errors: Record<string, string> = {};
		if (!recoveryEmail.trim()) errors.new_email = 'Enter the new login email.';
		if (!recoveryEvidence.trim()) errors.evidence_summary = 'Describe how you verified this person.';
		if (!recoveryReason.trim()) errors.reason = 'Enter a recovery reason.';
		recoveryFieldErrors = errors;
		if (Object.keys(errors).length > 0) return;

		recoveryMutation.mutate({
			new_email: recoveryEmail.trim(),
			evidence_summary: recoveryEvidence.trim(),
			reason: recoveryReason.trim(),
			idempotency_key: recoveryIdempotencyKey
		});
	}

	function confirmRecoveryStepUp() {
		if (pendingRecoveryInput) recoveryMutation.mutate(pendingRecoveryInput);
	}
</script>

<div class="team-access-actions">
	<table>
		<caption>Team members</caption>
		<thead>
			<tr>
				<th scope="col">Team member</th>
				<th scope="col">Email</th>
				<th scope="col">Role</th>
				<th scope="col">Joined</th>
				<th scope="col">Actions</th>
			</tr>
		</thead>
		<tbody>
			{#each members as member (member.user_id)}
				<tr>
					<td>{member.full_name ?? 'Unnamed'}</td>
					<td>{member.email ?? 'Not recorded'}</td>
					<td>
						{ROLE_LABELS[member.role] ?? member.role}
						{#if member.permission_overrides.length > 0}
							<ul class="team-access-actions__overrides">
								{#each member.permission_overrides as override (override.permission_key)}
									<li>
										<Badge status={override.override_state === 'grant' ? 'success' : 'warning'}>
											{permissionLabel(override.permission_key)}: {override.override_state ===
											'grant'
												? 'granted'
												: 'revoked'}
										</Badge>
									</li>
								{/each}
							</ul>
						{/if}
					</td>
					<td>{formatDateTime(member.created_at)}</td>
					<td>
						<div class="team-access-actions__buttons">
							<Button variant="secondary" variation="subtle" onclick={() => openCorrection(member)}
								>Fix profile</Button
							>
							{#if isAdministrator(member.role)}
								<Button
									variant="secondary"
									variation="subtle"
									onclick={() => openRecovery(member)}>Recover access</Button
								>
							{/if}
						</div>
					</td>
				</tr>
			{:else}
				<tr><td colspan="5">No team members yet.</td></tr>
			{/each}
		</tbody>
	</table>
</div>

<Dialog
	open={correctionMember !== null}
	title={correctionMember ? `Fix ${correctionMember.full_name ?? 'team member'}'s profile` : ''}
	onClose={closeCorrection}
>
	{#if correctionMember}
		<form class="team-access-actions__form" onsubmit={submitCorrection}>
			<p>
				Corrects a support case, not ordinary team management. The contractor owner or admin
				normally changes team access themselves.
			</p>
			<Input id="team-correction-name" label="Name" bind:value={correctionName} />
			{#if !isAdministrator(correctionMember.role)}
				<Input
					id="team-correction-email"
					label="Email"
					type="email"
					bind:value={correctionEmail}
				/>
			{:else}
				<p class="team-access-actions__note">
					This person is an owner or admin -- their login email can only change through
					administrator recovery.
				</p>
			{/if}
			<Input
				id="team-correction-reason"
				label="Correction reason"
				bind:value={correctionReason}
				invalid={Boolean(correctionFieldErrors.reason)}
				errorMessage={correctionFieldErrors.reason}
			/>
			{#if correctionFeedback}<p class="team-access-actions__error" role="alert">
					{correctionFeedback}
				</p>{/if}
			<div class="team-access-actions__dialog-actions">
				<Button type="submit" loading={correctionMutation.isPending}>Save correction</Button>
				<Button type="button" variant="secondary" variation="subtle" onclick={closeCorrection}
					>Cancel</Button
				>
			</div>
		</form>
	{/if}
</Dialog>

<Dialog
	open={recoveryMember !== null}
	title={recoveryMember ? `Recover ${recoveryMember.full_name ?? 'administrator'}'s access` : ''}
	onClose={closeRecovery}
>
	{#if recoveryMember}
		<form class="team-access-actions__form" onsubmit={submitRecovery}>
			<p>
				Only use this after verifying this person's identity yourself outside the app (a call,
				video, or similar). This revokes their current sessions and emails both the old and new
				address.
			</p>
			<Input
				id="team-recovery-email"
				label="New login email"
				type="email"
				bind:value={recoveryEmail}
				invalid={Boolean(recoveryFieldErrors.new_email)}
				errorMessage={recoveryFieldErrors.new_email}
			/>
			<Input
				id="team-recovery-evidence"
				label="How did you verify this person?"
				bind:value={recoveryEvidence}
				invalid={Boolean(recoveryFieldErrors.evidence_summary)}
				errorMessage={recoveryFieldErrors.evidence_summary}
			/>
			<Input
				id="team-recovery-reason"
				label="Recovery reason"
				bind:value={recoveryReason}
				invalid={Boolean(recoveryFieldErrors.reason)}
				errorMessage={recoveryFieldErrors.reason}
			/>
			{#if recoveryFeedback}<p class="team-access-actions__error" role="alert">
					{recoveryFeedback}
				</p>{/if}
			<div class="team-access-actions__dialog-actions">
				<Button type="submit" variation="destructive" loading={recoveryMutation.isPending}
					>Recover access</Button
				>
				<Button type="button" variant="secondary" variation="subtle" onclick={closeRecovery}
					>Cancel</Button
				>
			</div>
		</form>
	{/if}
</Dialog>

<OwnerReconfirmDialog
	bind:open={recoveryReconfirmOpen}
	title="Confirm administrator recovery"
	description="Recovering administrator access requires a recent password reconfirmation."
	confirmLabel="Recover access"
	onConfirm={confirmRecoveryStepUp}
/>

<style lang="scss">
	.team-access-actions {
		overflow-x: auto;
	}
	.team-access-actions table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		text-align: left;
	}
	.team-access-actions caption {
		padding-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: left;
	}
	.team-access-actions th,
	.team-access-actions td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		vertical-align: top;
	}
	.team-access-actions th {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.team-access-actions td:first-child {
		color: var(--color-heading);
		font-weight: 700;
	}
	.team-access-actions__overrides {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.team-access-actions__buttons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
		margin-left: auto;
	}
	.team-access-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.team-access-actions__form > p,
	.team-access-actions__note {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.team-access-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.team-access-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
