<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		communicationSendersKey,
		createCommunicationSender,
		fetchCommunicationSenders,
		SenderWriteError,
		updateCommunicationSender,
		type CommunicationEmailSender,
		type SenderDraft
	} from '$lib/communications/senders';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';

	const queryClient = useQueryClient();
	const sendersQuery = createQuery(() => ({
		queryKey: communicationSendersKey,
		queryFn: fetchCommunicationSenders,
		staleTime: 30_000
	}));
	let dialogMode = $state<'create' | 'edit' | null>(null);
	let editingSender = $state<CommunicationEmailSender | null>(null);
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let draft = $state<SenderDraft>(emptyDraft());
	let emailPrefix = $state('');

	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: dialogMode !== null,
		staleTime: 30_000
	}));
	const domains = $derived(sendersQuery.data?.domains ?? []);
	const healthyDomains = $derived(
		domains.filter((domain) => domain.lifecycle_state === 'verified')
	);
	const canCreate = $derived(healthyDomains.length > 0);
	const domainOptions = $derived(
		healthyDomains.map((domain) => ({ value: domain.id, label: domain.domain_name }))
	);
	const selectedDomainName = $derived(
		healthyDomains.find((domain) => domain.id === draft.domain_id)?.domain_name ?? ''
	);
	const memberOptions = $derived([
		{ value: '', label: 'No staff member assigned' },
		...(teamQuery.data ?? []).map((member) => ({
			value: member.id,
			label: member.full_name ?? 'Unnamed team member'
		}))
	]);
	const isEditing = $derived(dialogMode === 'edit');

	function emptyDraft(): SenderDraft {
		return {
			domain_id: '',
			email_address: '',
			display_name: '',
			assigned_user_id: null,
			is_organization_default: false,
			allows_manual: true,
			allows_automated: false,
			enabled: true
		};
	}

	function status(sender: CommunicationEmailSender) {
		if (sender.lifecycle_state === 'enabled') return { label: 'Ready', tone: 'success' as const };
		if (sender.lifecycle_state === 'disabled')
			return { label: 'Disabled', tone: 'inactive' as const };
		return { label: sender.lifecycle_state.replaceAll('_', ' '), tone: 'warning' as const };
	}

	function displayDomain(sender: CommunicationEmailSender) {
		return (
			domains.find((domain) => domain.id === sender.domain_id)?.domain_name ?? 'Unavailable domain'
		);
	}

	function openCreate() {
		editingSender = null;
		draft = { ...emptyDraft(), domain_id: healthyDomains[0]?.id ?? '' };
		emailPrefix = '';
		formError = '';
		fieldErrors = {};
		dialogMode = 'create';
	}

	function openEdit(sender: CommunicationEmailSender) {
		editingSender = sender;
		emailPrefix = '';
		draft = {
			domain_id: sender.domain_id,
			email_address: sender.email_address,
			display_name: sender.display_name,
			assigned_user_id: sender.assigned_user_id,
			is_organization_default: sender.is_organization_default,
			allows_manual: sender.allows_manual,
			allows_automated: sender.allows_automated,
			enabled: sender.lifecycle_state === 'enabled'
		};
		formError = '';
		fieldErrors = {};
		dialogMode = 'edit';
	}

	function closeDialog() {
		if (saving) return;
		dialogMode = null;
		editingSender = null;
	}

	function setAssignedUser(value: string) {
		draft.assigned_user_id = value || null;
	}

	async function prefetchTeam() {
		await queryClient.prefetchQuery({
			queryKey: assignableTeamKey,
			queryFn: fetchAssignableTeam,
			staleTime: 30_000
		});
	}

	async function submit() {
		if (saving || !dialogMode) return;
		let submissionDraft = draft;
		if (!editingSender) {
			const prefix = emailPrefix.trim();
			if (!prefix || prefix.includes('@') || !selectedDomainName) {
				fieldErrors = {
					email_address: prefix ? 'Type only the part before @.' : 'Enter the part before @.'
				};
				return;
			}
			submissionDraft = {
				...draft,
				email_address: `${prefix}@${selectedDomainName}`
			};
		}
		saving = true;
		formError = '';
		fieldErrors = {};
		try {
			if (editingSender) await updateCommunicationSender(editingSender.id, submissionDraft);
			else await createCommunicationSender(submissionDraft);
			await queryClient.invalidateQueries({ queryKey: communicationSendersKey });
			dialogMode = null;
			editingSender = null;
		} catch (error) {
			if (error instanceof SenderWriteError) {
				formError = error.message;
				fieldErrors = error.fieldErrors;
			} else
				formError =
					error instanceof Error ? error.message : 'The email identity could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head><title>Email identity · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="email-identities">
		<PageHeader
			eyebrow="Communications"
			title="Email identity"
			description="Choose the verified email addresses your team and future automations can use."
		>
			{#snippet actions()}
				<Button href={resolve('/settings')} variant="secondary" variation="subtle"
					>Back to settings</Button
				>
			{/snippet}
		</PageHeader>

		<SectionBlock
			title="Sender identities"
			hint="Domains are provisioned and verified by UCRM."
			icon={mailIcon}
			level={2}
		>
			{#snippet actions()}
				<Button disabled={!canCreate} onhover={() => void prefetchTeam()} onclick={openCreate}
					>Add sender</Button
				>
			{/snippet}
			{#if sendersQuery.isPending}
				<LoadingSkeleton variant="table" label="Loading email identities" />
			{:else if sendersQuery.isError}
				<ErrorState
					description="Email identities could not be loaded."
					retry={() => sendersQuery.refetch()}
				/>
			{:else if !domains.length}
				<EmptyState
					title="A sending domain is needed first"
					description="Ask your platform owner to provision and verify a sending domain before adding an email identity."
				/>
			{:else if !canCreate}
				<p class="email-identities__notice" role="status">
					A sending domain is still being checked. You can add an email identity once it is verified
					and healthy.
				</p>
			{:else if !sendersQuery.data?.senders.length}
				<EmptyState
					title="No email identities yet"
					description="Add the address your customers should see when your business emails them."
				>
					{#snippet action()}<Button onhover={() => void prefetchTeam()} onclick={openCreate}
							>Add sender</Button
						>{/snippet}
				</EmptyState>
			{:else}
				<div class="email-identities__table-wrap">
					<table>
						<thead
							><tr
								><th scope="col">Sender</th><th scope="col">Domain</th><th scope="col">Use</th><th
									scope="col">Status</th
								><th scope="col"><span class="email-identities__sr-only">Actions</span></th></tr
							></thead
						>
						<tbody>
							{#each sendersQuery.data.senders as sender (sender.id)}
								{@const senderStatus = status(sender)}
								<tr>
									<th scope="row"
										><strong>{sender.display_name}</strong><small
											>{sender.email_address}{sender.is_organization_default
												? ' · Default'
												: ''}</small
										></th
									>
									<td>{displayDomain(sender)}</td>
									<td
										>{sender.allows_manual && sender.allows_automated
											? 'Manual and automated'
											: sender.allows_manual
												? 'Manual'
												: 'Automated'}</td
									>
									<td><Badge status={senderStatus.tone}>{senderStatus.label}</Badge></td>
									<td
										><Button
											size="small"
											variant="secondary"
											variation="subtle"
											onhover={() => void prefetchTeam()}
											onclick={() => openEdit(sender)}>Edit</Button
										></td
									>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</SectionBlock>
	</div>
</PageContainer>

{#if dialogMode}
	<Dialog
		open
		title={isEditing ? 'Edit email identity' : 'Add email identity'}
		onClose={closeDialog}
	>
		<form
			class="email-identities__form"
			onsubmit={(event) => {
				event.preventDefault();
				void submit();
			}}
		>
			{#if formError}<p class="email-identities__error" role="alert">{formError}</p>{/if}
			{#if !isEditing}
				<Select
					id="sender-domain"
					ariaLabel="Sending domain"
					options={domainOptions}
					bind:value={draft.domain_id}
				/>
				<div class="email-identities__address">
					<Input
						id="sender-email-prefix"
						label="Email prefix"
						required
						autocapitalize="none"
						autocomplete="off"
						spellcheck={false}
						bind:value={emailPrefix}
						invalid={Boolean(fieldErrors.email_address)}
						errorMessage={fieldErrors.email_address}
					/>
					<span class="email-identities__domain" aria-hidden="true">@{selectedDomainName}</span>
				</div>
				<p class="email-identities__address-hint">
					The selected verified domain is added automatically.
				</p>
			{:else}
				<p class="email-identities__fixed-address">{draft.email_address}</p>
			{/if}
			<Input
				id="sender-display-name"
				label="Sender name"
				required
				bind:value={draft.display_name}
				invalid={Boolean(fieldErrors.display_name)}
				errorMessage={fieldErrors.display_name}
			/>
			{#if teamQuery.isPending}
				<LoadingSkeleton variant="text" rows={1} label="Loading team members" />
			{:else if teamQuery.isError}
				<p class="email-identities__error" role="alert">
					Your team could not be loaded. You can leave this sender unassigned.
				</p>
			{:else}
				<Select
					id="sender-assignment"
					ariaLabel="Assigned team member"
					options={memberOptions}
					value={draft.assigned_user_id ?? ''}
					onchange={setAssignedUser}
				/>
			{/if}
			<div class="email-identities__checks">
				<Checkbox
					id="sender-manual"
					label="Allow staff to use this sender"
					checked={draft.allows_manual}
					invalid={Boolean(fieldErrors.allows_manual)}
					onchange={(checked) => (draft.allows_manual = checked)}
				/>
				<Checkbox
					id="sender-automated"
					label="Allow future automations to use this sender"
					checked={draft.allows_automated}
					onchange={(checked) => (draft.allows_automated = checked)}
				/>
				<Checkbox
					id="sender-default"
					label="Use as the business default"
					description="Used when no eligible staff or automation sender is chosen."
					checked={draft.is_organization_default}
					onchange={(checked) => (draft.is_organization_default = checked)}
				/>
				{#if isEditing}<Checkbox
						id="sender-enabled"
						label="Email identity is active"
						checked={draft.enabled}
						onchange={(checked) => (draft.enabled = checked)}
					/>{/if}
			</div>
			<div class="email-identities__actions">
				<Button type="submit" loading={saving}>{isEditing ? 'Save changes' : 'Add sender'}</Button
				><Button
					type="button"
					variant="secondary"
					variation="subtle"
					disabled={saving}
					onclick={closeDialog}>Cancel</Button
				>
			</div>
		</form>
	</Dialog>
{/if}

<style lang="scss">
	.email-identities {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.email-identities :global(.section-block) {
		--section-block-notch: var(--color-surface);
	}
	.email-identities__notice,
	.email-identities__fixed-address {
		margin: 0;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.email-identities__table-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.email-identities table {
		width: 100%;
		min-width: 760px;
		border-collapse: collapse;
		color: var(--color-text);
	}
	.email-identities th,
	.email-identities td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}
	.email-identities thead th {
		background: var(--color-surface--background--subtle);
		color: var(--color-heading);
		font-weight: 700;
	}
	.email-identities tbody tr:last-child th,
	.email-identities tbody tr:last-child td {
		border-bottom: 0;
	}
	.email-identities tbody th strong,
	.email-identities tbody th small {
		display: block;
	}
	.email-identities tbody th small {
		margin-top: var(--space-smallest);
		color: var(--color-text--secondary);
		font-weight: 400;
	}
	.email-identities__form,
	.email-identities__checks {
		display: grid;
		gap: var(--space-base);
	}
	.email-identities__address {
		display: flex;
		align-items: stretch;
		gap: var(--space-small);
	}
	.email-identities__address :global(.input) {
		flex: 1 1 12rem;
	}
	.email-identities__domain {
		display: flex;
		align-items: center;
		max-width: min(100%, 22rem);
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.email-identities__address-hint {
		margin: calc(var(--space-small) * -1) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-identities__error {
		margin: 0;
		color: var(--color-critical);
	}
	.email-identities__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.email-identities__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
	@media (max-width: 639px) {
		.email-identities {
			gap: var(--space-base);
		}
		.email-identities__actions {
			justify-content: flex-start;
		}
		.email-identities__address {
			flex-direction: column;
		}
		.email-identities__domain {
			min-height: var(--space-largest);
			max-width: none;
		}
	}
</style>
