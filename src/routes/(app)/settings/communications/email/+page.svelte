<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmailSetupCard from '$lib/components/settings/EmailSetupCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		communicationSendersKey,
		createCommunicationSender,
		fetchCommunicationSenders,
		fetchSenderRemovalImpact,
		removeCommunicationSender,
		senderRemovalImpactKey,
		SenderWriteError,
		updateCommunicationSender,
		type CommunicationEmailSender,
		type SenderDraft
	} from '$lib/communications/senders';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import atIcon from '@tabler/icons/outline/at.svg?raw';
	import gaugeIcon from '@tabler/icons/outline/gauge.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// This billing period's email standing. `optional` is ordinary business email; `essential` is the
	// protected reserve that keeps requested quotes, invoices, receipts and direct replies moving
	// after the ordinary allowance is spent.
	type EmailUsage = {
		period_ends_at: string;
		organization_timezone: string;
		optional_limit_state: string | null;
		optional_limit_value: number | null;
		optional_used: number;
		essential_limit_state: string | null;
		essential_limit_value: number | null;
		essential_used: number;
		essential_reserve_exhausted: boolean;
	};

	const usageKey = ['settings', 'communications', 'email-usage'] as const;
	const usageQuery = createQuery<EmailUsage | null>(() => ({
		queryKey: usageKey,
		queryFn: async () => {
			const response = await fetch('/api/settings/communications/usage');
			const result = (await response.json()) as (EmailUsage & { error?: string }) | null;
			if (!response.ok) throw new Error(result?.error ?? 'Email usage could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));
	const usage = $derived(usageQuery.data ?? null);
	const optionalRemaining = $derived(remaining(usage?.optional_limit_value, usage?.optional_used));
	const essentialRemaining = $derived(
		remaining(usage?.essential_limit_value, usage?.essential_used)
	);

	function remaining(limit: number | null | undefined, used: number | undefined) {
		if (limit == null || used == null) return null;
		return Math.max(0, limit - used);
	}

	function countLabel(value: number) {
		return new Intl.NumberFormat().format(value);
	}

	// The meter head shows the used count large with its context small: "N of M", or
	// "sent · no limit" after the count when the period has no numeric allowance.
	function meterTail(state: string | null, limit: number | null) {
		if (state === 'unlimited') return 'sent · no limit';
		if (state !== 'numeric' || limit == null) return '';
		return `of ${countLabel(limit)}`;
	}

	function meterPercent(limit: number | null, used: number) {
		if (!limit) return 0;
		return Math.min(100, Math.round((used / limit) * 100));
	}

	function resetLabel(endsAt: string, timeZone: string) {
		return new Intl.DateTimeFormat(undefined, {
			dateStyle: 'medium',
			timeStyle: 'short',
			timeZone
		}).format(new Date(endsAt));
	}

	const queryClient = useQueryClient();
	const toast = getToastManager();
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

	// Removal: the impact loads only once the owner reaches for Remove (hover prefetch), never with the page.
	let removingSender = $state<CommunicationEmailSender | null>(null);
	let removalKey = $state('');
	let removing = $state(false);
	let removalError = $state('');
	const removalImpactQuery = createQuery(() => ({
		queryKey: senderRemovalImpactKey(removingSender?.id ?? ''),
		queryFn: () => fetchSenderRemovalImpact(removingSender!.id),
		enabled: removingSender !== null,
		staleTime: 10_000
	}));
	const removalImpact = $derived(removalImpactQuery.data ?? null);

	function prefetchRemovalImpact(senderId: string) {
		void queryClient.prefetchQuery({
			queryKey: senderRemovalImpactKey(senderId),
			queryFn: () => fetchSenderRemovalImpact(senderId),
			staleTime: 10_000
		});
	}

	function openRemoval() {
		if (!editingSender || saving) return;
		removingSender = editingSender;
		removalKey = crypto.randomUUID();
		removalError = '';
		dialogMode = null;
		editingSender = null;
	}

	function closeRemoval() {
		if (removing) return;
		removingSender = null;
	}

	async function confirmRemoval() {
		if (!removingSender || removing) return;
		removing = true;
		removalError = '';
		try {
			await removeCommunicationSender(removingSender.id, removalKey);
			toast.success('Email identity removed.');
			await queryClient.invalidateQueries({ queryKey: communicationSendersKey });
			removingSender = null;
		} catch (error) {
			removalError =
				error instanceof Error ? error.message : 'The email identity could not be removed.';
		} finally {
			removing = false;
		}
	}

	function emptyDraft(): SenderDraft {
		return {
			domain_id: '',
			email_address: '',
			display_name: '',
			assigned_user_id: null,
			is_organization_default: false,
			allows_manual: true,
			allows_automated: true,
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
			toast.success(editingSender ? 'Email identity updated.' : 'Email identity added.');
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

<PageContainer variant="open">
	<div class="email-identities record-detail--cards">
		<SettingsPageHeader
			title="Email identity"
			description="Choose the verified email addresses your team and automations can use."
			icon={atIcon}
			tone="task"
			presentation="communication"
		/>

		<SectionBlock
			title="Email included this period"
			hint="Business email is included in your package and resets every billing period."
			icon={gaugeIcon}
			level={2}
		>
			{#if usageQuery.isPending}
				<LoadingSkeleton variant="text" rows={3} label="Loading email usage" />
			{:else if usageQuery.isError}
				<ErrorState
					description="Email usage could not be loaded."
					retry={() => usageQuery.refetch()}
				/>
			{:else if !usage}
				<p class="email-identities__notice" role="status">
					Your billing period has not started yet, so there is nothing to count.
				</p>
			{:else}
				{#if usage.essential_reserve_exhausted}
					<p class="email-usage__warning" role="status">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
						<span class="email-usage__warning-icon" aria-hidden="true">{@html alertIcon}</span>
						<span
							>Your protected reserve is used up, so quotes, invoices, receipts and replies are
							waiting instead of going out. They send as soon as the period resets on {resetLabel(
								usage.period_ends_at,
								usage.organization_timezone
							)}, or sooner if we raise your allowance.</span
						>
					</p>
				{/if}
				<div class="email-usage__meters">
					<div class="email-usage__meter">
						<div class="email-usage__meter-head">
							<strong>Business email</strong>
							<span class="email-usage__meter-value">
								{countLabel(usage.optional_used)}
								{#if meterTail(usage.optional_limit_state, usage.optional_limit_value)}
									<small>{meterTail(usage.optional_limit_state, usage.optional_limit_value)}</small>
								{/if}
							</span>
						</div>
						{#if usage.optional_limit_state === 'numeric' && usage.optional_limit_value != null}
							<div
								class="email-usage__track"
								role="meter"
								aria-label="Business email used this period"
								aria-valuenow={usage.optional_used}
								aria-valuemin={0}
								aria-valuemax={usage.optional_limit_value}
							>
								<span
									class="email-usage__fill"
									style="--email-usage-percent: {meterPercent(
										usage.optional_limit_value,
										usage.optional_used
									)}%"
								></span>
							</div>
							<small
								>{countLabel(optionalRemaining ?? 0)} recipients left before ordinary email pauses.</small
							>
						{:else}
							<small>No limit applies to your ordinary business email this period.</small>
						{/if}
					</div>
					<div class="email-usage__meter">
						<div class="email-usage__meter-head">
							<strong>Protected reserve</strong>
							<span class="email-usage__meter-value">
								{countLabel(usage.essential_used)}
								{#if meterTail(usage.essential_limit_state, usage.essential_limit_value)}
									<small
										>{meterTail(usage.essential_limit_state, usage.essential_limit_value)}</small
									>
								{/if}
							</span>
						</div>
						{#if usage.essential_limit_state === 'numeric' && usage.essential_limit_value != null}
							<div
								class="email-usage__track"
								role="meter"
								aria-label="Protected reserve used this period"
								aria-valuenow={usage.essential_used}
								aria-valuemin={0}
								aria-valuemax={usage.essential_limit_value}
							>
								<span
									class="email-usage__fill email-usage__fill--reserve"
									style="--email-usage-percent: {meterPercent(
										usage.essential_limit_value,
										usage.essential_used
									)}%"
								></span>
							</div>
							<small
								>{countLabel(essentialRemaining ?? 0)} recipients left for quotes, invoices, receipts,
								security notices and replies.</small
							>
						{:else}
							<small
								>No limit applies to quotes, invoices, receipts, security notices and replies.</small
							>
						{/if}
					</div>
				</div>
				<p class="email-usage__reset">
					<span class="email-usage__reset-icon" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
						{@html calendarIcon}
					</span>
					<span>Resets {resetLabel(usage.period_ends_at, usage.organization_timezone)}.</span>
				</p>
			{/if}
		</SectionBlock>

		<EmailSetupCard />

		<SectionBlock
			class="section-block--flush"
			title="Sender identities"
			hint="Domains are provisioned and verified by UCRM."
			icon={mailIcon}
			level={2}
		>
			{#snippet actions()}
				<Button disabled={!canCreate} onhover={() => void prefetchTeam()} onclick={openCreate}>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="email-identities__action-icon" aria-hidden="true">{@html plusIcon}</span>
					Add sender</Button
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
					description="Request email setup above. You can add senders once UCRM has set up and verified your domain."
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
				<DataTable
					variant="card"
					caption="Email sender identities"
					columns={[
						{ key: 'sender', label: 'Sender' },
						{ key: 'domain', label: 'Domain' },
						{ key: 'use', label: 'Use' },
						{ key: 'status', label: 'Status' }
					]}
					items={sendersQuery.data.senders}
					rowId={(sender) => sender.id}
				>
					{#snippet row(sender)}
						{@const senderStatus = status(sender)}
						<th scope="row">
							<div class="email-identities__sender">
								<Avatar id={sender.id} name={sender.display_name} size="base" />
								<div class="email-identities__sender-id">
									<strong>{sender.display_name}</strong>
									<small>
										<span>{sender.email_address}</span>
										{#if sender.is_organization_default}
											<Badge size="small" class="email-identities__default-chip">Default</Badge>
										{/if}
									</small>
								</div>
							</div>
						</th>
						<td>{displayDomain(sender)}</td>
						<td
							>{sender.allows_manual && sender.allows_automated
								? 'Manual and automated'
								: sender.allows_manual
									? 'Manual'
									: 'Automated'}</td
						>
						<td
							><StatusBadge status={senderStatus.tone} size="compact"
								>{senderStatus.label}</StatusBadge
							></td
						>
					{/snippet}
					{#snippet rowActions(sender)}
						<Button
							size="small"
							variant="secondary"
							variation="subtle"
							onhover={() => void prefetchTeam()}
							onclick={() => openEdit(sender)}>Edit</Button
						>
					{/snippet}
				</DataTable>
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
					label="Allow automations to use this sender"
					description="Automatic messages, like review requests and follow-ups, go out from the business default."
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
				{#if editingSender}
					{@const senderId = editingSender.id}
					<span class="email-identities__remove"
						><Button
							type="button"
							variant="tertiary"
							variation="destructive"
							disabled={saving}
							onhover={() => prefetchRemovalImpact(senderId)}
							onclick={openRemoval}>Remove sender</Button
						></span
					>
				{/if}
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

{#if removingSender}
	<ConfirmDialog
		open
		title="Remove this email identity?"
		icon={trashIcon}
		tone="critical"
		destructive
		confirmLabel="Remove sender"
		loading={removing}
		confirmDisabled={!removalImpact}
		onConfirm={() => void confirmRemoval()}
		onClose={closeRemoval}
	>
		<p class="email-removal__lead">
			<strong>{removingSender.email_address}</strong> will stop sending right away. Past emails and customer
			replies stay in your inbox, and you can add this address again later.
		</p>
		{#if removalImpactQuery.isPending}
			<LoadingSkeleton variant="text" rows={2} label="Checking what this affects" />
		{:else if removalImpactQuery.isError}
			<p class="email-identities__error" role="alert">
				What this affects could not be checked. Close this and try again.
			</p>
		{:else if removalImpact}
			{@const effects = [
				removalImpact.is_organization_default
					? removalImpact.other_enabled_sender_count > 0
						? 'This is your business default. Choose another default so automatic emails keep a sender.'
						: 'This is your only active sender. Quotes, invoices and other automatic emails wait until you add a new one.'
					: null,
				removalImpact.assigned_member_name
					? `${removalImpact.assigned_member_name} can no longer send email from it.`
					: null,
				removalImpact.queued_email_count > 0
					? `${removalImpact.queued_email_count} email${removalImpact.queued_email_count === 1 ? ' is' : 's are'} still waiting to send from it. Staff emails are held for review; automatic ones are cancelled.`
					: null
			].filter((effect) => effect !== null)}
			{#if effects.length}
				<ul class="email-removal__effects">
					{#each effects as effect (effect)}<li>{effect}</li>{/each}
				</ul>
			{/if}
		{/if}
		{#if removalError}<p class="email-identities__error" role="alert">{removalError}</p>{/if}
	</ConfirmDialog>
{/if}

<style lang="scss">
	.email-identities {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.email-identities {
		gap: 20px;
	}
	/* App-look cards: each block is a white card on the app background. The shared card rules (the
	   `record-detail--cards` context) put the heading, hint and actions inside the card header; the page
	   only restores the framed icon tile, which sits beside both header lines as the approved frame shows. */
	.email-identities.record-detail--cards :global(.section-block > .section-block__title) {
		padding-left: 72px;
	}
	.email-identities.record-detail--cards :global(.section-block:has(> .section-block__hint)) {
		> :global(.section-block__hint) {
			margin-left: 72px;
		}
	}
	.email-identities.record-detail--cards :global(.section-block .section-block__icon) {
		position: absolute;
		top: 20px;
		left: 24px;
		display: grid;
		place-items: center;
		width: 36px;
		height: 36px;
		border-radius: 11px;
		background: var(--color-informative--surface);
	}
	.email-identities.record-detail--cards :global(.section-block .section-block__icon svg) {
		width: 18px;
		height: 18px;
		color: var(--color-informative--onSurface);
	}
	.email-identities__action-icon {
		display: inline-flex;
		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
	.email-identities__notice,
	.email-identities__fixed-address {
		margin: 0;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.email-usage__warning {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.email-usage__warning-icon {
		display: flex;
		flex: 0 0 auto;
		align-self: flex-start;
		padding: var(--space-smallest);
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-warning);
	}
	.email-usage__warning-icon :global(svg) {
		width: var(--typography--fontSize-large);
		height: var(--typography--fontSize-large);
	}
	.email-identities .email-usage__meters {
		display: grid;
		margin: 0 24px 14px;
		gap: 16px;
		grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
	}
	.email-usage__meter {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 16px 18px;
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.email-usage__meter-head {
		display: flex;
		align-items: baseline;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.email-usage__meter-head > strong {
		color: var(--color-heading);
		font-weight: 600;
	}
	.email-usage__meter-value {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 700;
		line-height: var(--typography--lineHeight-minuscule);
	}
	.email-usage__meter-value small {
		margin-left: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	.email-usage__meter small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-usage__track {
		height: var(--space-small);
		border-radius: var(--radius-circle);
		background: var(--color-surface--active);
		overflow: hidden;
	}
	.email-usage__fill {
		display: block;
		width: var(--email-usage-percent, 0%);
		height: 100%;
		border-radius: inherit;
		background: var(--color-interactive);
	}
	.email-usage__fill--reserve {
		background: var(--color-warning);
	}
	.email-identities .email-usage__reset {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: 0 24px 22px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-usage__reset-icon {
		display: flex;
		flex: 0 0 auto;
	}
	.email-usage__reset-icon :global(svg) {
		width: 14px;
		height: 14px;
	}
	/* Sender row: avatar beside the identity block. The Default chip rides inline after the address. */
	.email-identities__sender {
		display: flex;
		align-items: center;
		gap: var(--space-base);
	}
	.email-identities__sender-id {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	.email-identities__sender-id strong {
		color: var(--color-heading);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
	}
	.email-identities__sender-id small {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		line-height: var(--typography--lineHeight-large);
		overflow-wrap: anywhere;
	}
	.email-identities__sender-id :global(.email-identities__default-chip) {
		color: var(--color-surface);
		background: var(--color-surface--reverse);
	}
	/* The approved settings-table look needs fewer columns than the shared card table's default
	   width floor, so the horizontal scroll only starts where the old table used to. */
	.email-identities :global(.data-table--card) {
		--data-table-min-width: 760px;
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
	.email-identities__remove {
		margin-right: auto;
	}
	.email-removal__lead {
		margin: 0;
	}
	.email-removal__effects {
		display: grid;
		gap: var(--space-small);
		margin: var(--space-base) 0 0;
		padding-left: var(--space-large);
		color: var(--color-text);
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
