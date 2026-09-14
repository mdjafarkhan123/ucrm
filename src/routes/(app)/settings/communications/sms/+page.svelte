<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchSmsRegistration,
		saveSmsRegistrationDraft,
		startSmsRegistration,
		submitSmsRegistration,
		smsRegistrationKey,
		smsRegistrationBadge,
		SmsRegistrationWriteError,
		type SmsRegistrationAnswers
	} from '$lib/communications/sms-registration';
	import deviceMobileMessageIcon from '@tabler/icons/outline/device-mobile-message.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const homeQuery = createQuery(() => ({
		queryKey: smsRegistrationKey,
		queryFn: fetchSmsRegistration,
		staleTime: 15_000
	}));

	const businessTypeOptions = [
		{ value: 'sole_proprietorship', label: 'Sole proprietorship' },
		{ value: 'partnership', label: 'Partnership' },
		{ value: 'limited_liability_company', label: 'Limited liability company' },
		{ value: 'cooperative', label: 'Cooperative' },
		{ value: 'nonprofit_corporation', label: 'Nonprofit corporation' },
		{ value: 'corporation', label: 'Corporation' },
		{ value: 'other', label: 'Other' }
	];
	const consentMethodOptions = [
		{ value: 'website_form', label: 'Website form' },
		{ value: 'paper_form', label: 'Paper form' },
		{ value: 'verbal', label: 'Verbal, in person or on a call' },
		{ value: 'text_initiated', label: 'Customer texted us first' },
		{ value: 'other', label: 'Other' }
	];
	const estimatedVolumeOptions = [
		{ value: 'under_500', label: 'Under 500 a month' },
		{ value: '500_2000', label: '500–2,000 a month' },
		{ value: '2001_10000', label: '2,001–10,000 a month' },
		{ value: 'over_10000', label: 'Over 10,000 a month' }
	];

	function emptyAnswers(): SmsRegistrationAnswers {
		return {
			legal_business_name: '',
			business_type: '',
			business_registration_id_type: '',
			business_registration_id: '',
			website_url: '',
			business_address: {
				line1: '',
				line2: '',
				city: '',
				region: '',
				postal_code: '',
				country_code: 'US'
			},
			authorized_representative: {
				first_name: '',
				last_name: '',
				business_title: '',
				job_position: '',
				email: '',
				phone_number: ''
			},
			messaging: {
				description: '',
				consent_method: '',
				consent_description: '',
				sample_messages: ['', ''],
				privacy_policy_url: '',
				terms_url: '',
				estimated_monthly_messages: ''
			}
		};
	}

	let starting = $state(false);
	let draft = $state<SmsRegistrationAnswers>(emptyAnswers());
	let hydratedRevision = $state<number | null>(null);
	let saving = $state(false);
	let submitting = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let confirmAuthorized = $state(false);

	const registration = $derived(homeQuery.data?.registration ?? null);
	const readiness = $derived(
		homeQuery.data?.readiness ?? {
			effective_mode: 'off' as const,
			readiness_state: 'needs_setup' as const,
			live_sender_count: 0
		}
	);
	const isEditable = $derived(
		registration
			? registration.status === 'waiting_for_info' || registration.status === 'action_needed'
			: false
	);

	// The form hydrates from the server's draft_answers exactly once per revision, so typing doesn't get
	// clobbered by a background refetch but a save from another tab still shows up.
	$effect(() => {
		if (!registration || hydratedRevision === registration.draft_revision) return;
		const saved = registration.draft_answers ?? {};
		const base = emptyAnswers();
		draft = {
			...base,
			...saved,
			business_address: { ...base.business_address, ...saved.business_address },
			authorized_representative: {
				...base.authorized_representative,
				...saved.authorized_representative
			},
			messaging: {
				...base.messaging,
				...saved.messaging,
				sample_messages:
					saved.messaging?.sample_messages && saved.messaging.sample_messages.length
						? [...saved.messaging.sample_messages]
						: ['', '']
			}
		};
		hydratedRevision = registration.draft_revision;
	});

	function registrationStatusLabel(status: string | undefined) {
		switch (status) {
			case 'waiting_for_info':
				return 'Draft';
			case 'under_review':
				return 'Submitted · pending review';
			case 'action_needed':
				return 'Needs information';
			case 'approved':
				return 'Approved';
			default:
				return 'Not started';
		}
	}

	async function handleStart() {
		if (starting) return;
		starting = true;
		try {
			await startSmsRegistration();
			hydratedRevision = null;
			await queryClient.invalidateQueries({ queryKey: smsRegistrationKey });
			toast.success('Registration started.');
		} catch (cause) {
			toast.error(
				cause instanceof Error ? cause.message : 'The registration could not be started.'
			);
		} finally {
			starting = false;
		}
	}

	// Empty strings and untouched sub-objects are dropped so a partial save never trips the "if present it
	// must be valid" rule the draft schema still applies to whatever fields are included.
	function pruneDraft(answers: SmsRegistrationAnswers) {
		const pruned: Record<string, unknown> = {};
		if (answers.legal_business_name.trim())
			pruned.legal_business_name = answers.legal_business_name.trim();
		if (answers.business_type) pruned.business_type = answers.business_type;
		if (answers.business_registration_id_type.trim())
			pruned.business_registration_id_type = answers.business_registration_id_type.trim();
		if (answers.business_registration_id.trim())
			pruned.business_registration_id = answers.business_registration_id.trim();
		if (answers.website_url.trim()) pruned.website_url = answers.website_url.trim();

		const address = Object.fromEntries(
			Object.entries(answers.business_address).filter(([, value]) => (value ?? '').trim())
		);
		if (Object.keys(address).length) pruned.business_address = address;

		const rep = Object.fromEntries(
			Object.entries(answers.authorized_representative).filter(([, value]) => (value ?? '').trim())
		);
		if (Object.keys(rep).length) pruned.authorized_representative = rep;

		const messages = answers.messaging.sample_messages?.map((m) => m.trim()).filter(Boolean) ?? [];
		const messaging: Record<string, unknown> = {};
		if (answers.messaging.description?.trim())
			messaging.description = answers.messaging.description.trim();
		if (answers.messaging.consent_method)
			messaging.consent_method = answers.messaging.consent_method;
		if (answers.messaging.consent_description?.trim())
			messaging.consent_description = answers.messaging.consent_description.trim();
		if (messages.length >= 2) messaging.sample_messages = messages;
		if (answers.messaging.privacy_policy_url?.trim())
			messaging.privacy_policy_url = answers.messaging.privacy_policy_url.trim();
		if (answers.messaging.terms_url?.trim())
			messaging.terms_url = answers.messaging.terms_url.trim();
		if (answers.messaging.estimated_monthly_messages)
			messaging.estimated_monthly_messages = answers.messaging.estimated_monthly_messages;
		if (Object.keys(messaging).length) pruned.messaging = messaging;

		return pruned;
	}

	async function saveDraft() {
		if (!registration || saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		try {
			await saveSmsRegistrationDraft(registration.id, {
				expected_revision: registration.draft_revision,
				questionnaire_version: 1,
				answers: pruneDraft(draft)
			});
			await queryClient.invalidateQueries({ queryKey: smsRegistrationKey });
			toast.success('Draft saved.');
		} catch (cause) {
			if (cause instanceof SmsRegistrationWriteError) {
				formError = cause.message;
				fieldErrors = cause.fieldErrors;
			} else formError = cause instanceof Error ? cause.message : 'The draft could not be saved.';
		} finally {
			saving = false;
		}
	}

	async function submit() {
		if (!registration || submitting) return;
		if (!confirmAuthorized) {
			formError = 'Confirm that you are authorized to represent this business.';
			return;
		}
		submitting = true;
		formError = '';
		fieldErrors = {};
		try {
			const messaging = {
				...draft.messaging,
				sample_messages: draft.messaging.sample_messages?.map((m) => m.trim()).filter(Boolean) ?? []
			};
			await submitSmsRegistration(registration.id, {
				expected_revision: registration.draft_revision,
				questionnaire_version: 1,
				answers: { ...draft, messaging } as SmsRegistrationAnswers,
				confirm_authorized_representative: true
			});
			await queryClient.invalidateQueries({ queryKey: smsRegistrationKey });
			confirmAuthorized = false;
			toast.success('Registration submitted for review.');
		} catch (cause) {
			if (cause instanceof SmsRegistrationWriteError) {
				formError = cause.message;
				fieldErrors = cause.fieldErrors;
			} else
				formError =
					cause instanceof Error ? cause.message : 'The registration could not be submitted.';
		} finally {
			submitting = false;
		}
	}

	function addSampleMessage() {
		if ((draft.messaging.sample_messages?.length ?? 0) >= 5) return;
		draft.messaging.sample_messages = [...(draft.messaging.sample_messages ?? []), ''];
	}
	function removeSampleMessage(index: number) {
		if ((draft.messaging.sample_messages?.length ?? 0) <= 2) return;
		draft.messaging.sample_messages = (draft.messaging.sample_messages ?? []).filter(
			(_, i) => i !== index
		);
	}
</script>

<svelte:head><title>Phone & SMS · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="sms-settings">
		<PageHeader
			eyebrow="Communications"
			title="Phone & SMS"
			description="Understand what is ready and what needs attention."
		>
			{#snippet actions()}
				<Button href={resolve('/settings')} variant="secondary" variation="subtle"
					>Back to settings</Button
				>
			{/snippet}
		</PageHeader>

		{#if homeQuery.isPending}
			<LoadingSkeleton variant="card" rows={3} />
		{:else if homeQuery.isError}
			<ErrorState
				description="Phone & SMS could not be loaded."
				retry={() => homeQuery.refetch()}
			/>
		{:else}
			<SectionBlock title="Readiness" icon={deviceMobileMessageIcon} level={2}>
				<div class="sms-settings__facts">
					<div class="sms-settings__fact">
						<span>SMS mode</span>
						<strong>{readiness.effective_mode === 'operational' ? 'On' : 'Off'}</strong>
					</div>
					<div class="sms-settings__fact">
						<span>Registration</span>
						<StatusBadge status={smsRegistrationBadge(readiness.readiness_state).tone}
							>{registrationStatusLabel(registration?.status)}</StatusBadge
						>
					</div>
					<div class="sms-settings__fact">
						<span>Ready numbers</span>
						<strong>{readiness.live_sender_count}</strong>
					</div>
					<div class="sms-settings__fact">
						<span>Outbound availability</span>
						<strong
							>{readiness.readiness_state === 'ready' ? 'Available' : 'Not yet available'}</strong
						>
					</div>
				</div>

				{#if !registration}
					<p class="sms-settings__notice" role="status">
						Start registration to let customers text your business and receive their replies.
					</p>
					<Button loading={starting} onclick={handleStart}>Start registration</Button>
				{:else if registration.status === 'action_needed'}
					<p class="sms-settings__notice sms-settings__notice--critical" role="alert">
						This registration needs a fix before it can be resubmitted.
					</p>
					<Button href="#registration" variant="secondary">Fix registration</Button>
				{:else if registration.status === 'under_review'}
					<p class="sms-settings__notice" role="status">
						Submitted{registration.submitted_at
							? ` on ${new Date(registration.submitted_at).toLocaleDateString()}`
							: ''} and waiting on a provider decision. We'll update this as soon as it arrives.
					</p>
				{:else if registration.status === 'approved' && readiness.readiness_state !== 'ready'}
					<p class="sms-settings__notice" role="status">
						Approved. A sending number still needs to be linked to finish setup.
					</p>
				{/if}
			</SectionBlock>

			{#if registration}
				<SectionBlock
					title="Registration"
					id="registration"
					icon={deviceMobileMessageIcon}
					level={2}
				>
					{#if registration.status === 'action_needed' && registration.required_fixes}
						<p class="sms-settings__notice sms-settings__notice--critical" role="alert">
							<strong>Required fixes:</strong>
							{registration.required_fixes}
						</p>
					{/if}
					{#if !isEditable}
						<p class="sms-settings__notice" role="status">
							{registration.status === 'approved'
								? 'This registration is approved and can no longer be edited.'
								: 'This registration is under review and can’t be edited until a decision arrives.'}
						</p>
					{/if}

					{#if formError}<p class="sms-settings__error" role="alert">{formError}</p>{/if}

					<form
						class="sms-settings__form"
						onsubmit={(event) => {
							event.preventDefault();
						}}
					>
						<div class="sms-settings__group">
							<h3>Business identity</h3>
							<Input
								id="sms-legal-name"
								label="Legal business name"
								required
								disabled={!isEditable}
								bind:value={draft.legal_business_name}
								invalid={Boolean(fieldErrors.legal_business_name)}
								errorMessage={fieldErrors.legal_business_name}
							/>
							<Select
								id="sms-business-type"
								label="Business type"
								options={businessTypeOptions}
								disabled={!isEditable}
								bind:value={draft.business_type}
							/>
							<Input
								id="sms-registration-id-type"
								label="Registration ID type (e.g. EIN)"
								disabled={!isEditable}
								bind:value={draft.business_registration_id_type}
							/>
							<Input
								id="sms-registration-id"
								label="Business registration ID"
								disabled={!isEditable}
								bind:value={draft.business_registration_id}
								invalid={Boolean(fieldErrors.business_registration_id)}
								errorMessage={fieldErrors.business_registration_id}
							/>
							<Input
								id="sms-website-url"
								label="Website"
								type="url"
								placeholder="https://example.com"
								disabled={!isEditable}
								bind:value={draft.website_url}
								invalid={Boolean(fieldErrors.website_url)}
								errorMessage={fieldErrors.website_url}
							/>
						</div>

						<div class="sms-settings__group">
							<h3>Business address</h3>
							<Input
								id="sms-address-line1"
								label="Street address"
								disabled={!isEditable}
								bind:value={draft.business_address.line1}
							/>
							<Input
								id="sms-address-line2"
								label="Suite / unit (optional)"
								disabled={!isEditable}
								bind:value={draft.business_address.line2}
							/>
							<Input
								id="sms-address-city"
								label="City"
								disabled={!isEditable}
								bind:value={draft.business_address.city}
							/>
							<Input
								id="sms-address-region"
								label="State / province"
								disabled={!isEditable}
								bind:value={draft.business_address.region}
							/>
							<Input
								id="sms-address-postal"
								label="Postal code"
								disabled={!isEditable}
								bind:value={draft.business_address.postal_code}
							/>
							<Input
								id="sms-address-country"
								label="Country code"
								maxlength={2}
								disabled={!isEditable}
								bind:value={draft.business_address.country_code}
							/>
						</div>

						<div class="sms-settings__group">
							<h3>Authorized representative</h3>
							<Input
								id="sms-rep-first-name"
								label="First name"
								disabled={!isEditable}
								bind:value={draft.authorized_representative.first_name}
							/>
							<Input
								id="sms-rep-last-name"
								label="Last name"
								disabled={!isEditable}
								bind:value={draft.authorized_representative.last_name}
							/>
							<Input
								id="sms-rep-title"
								label="Business title"
								disabled={!isEditable}
								bind:value={draft.authorized_representative.business_title}
							/>
							<Input
								id="sms-rep-position"
								label="Job position"
								disabled={!isEditable}
								bind:value={draft.authorized_representative.job_position}
							/>
							<Input
								id="sms-rep-email"
								label="Email"
								type="email"
								disabled={!isEditable}
								bind:value={draft.authorized_representative.email}
							/>
							<Input
								id="sms-rep-phone"
								label="Phone (e.g. +15125550100)"
								disabled={!isEditable}
								bind:value={draft.authorized_representative.phone_number}
							/>
						</div>

						<div class="sms-settings__group">
							<h3>Messaging</h3>
							<Textarea
								id="sms-messaging-description"
								label="How will you use texting?"
								rows={3}
								maxlength={2000}
								disabled={!isEditable}
								bind:value={draft.messaging.description}
							/>
							<Select
								id="sms-consent-method"
								label="How do customers agree to receive texts?"
								options={consentMethodOptions}
								disabled={!isEditable}
								bind:value={draft.messaging.consent_method}
							/>
							<Textarea
								id="sms-consent-description"
								label="Describe how consent is collected"
								rows={2}
								maxlength={2000}
								disabled={!isEditable}
								bind:value={draft.messaging.consent_description}
							/>

							<div class="sms-settings__samples">
								<span class="sms-settings__group-label">Sample messages (2–5)</span>
								<!-- eslint-disable-next-line @typescript-eslint/no-unused-vars -->
								{#each draft.messaging.sample_messages ?? [] as _, index (index)}
									<div class="sms-settings__sample-row">
										<Input
											id={`sms-sample-message-${index}`}
											label={`Sample message ${index + 1}`}
											hideLabel
											maxlength={1600}
											disabled={!isEditable}
											bind:value={draft.messaging.sample_messages![index]}
										/>
										{#if isEditable && (draft.messaging.sample_messages?.length ?? 0) > 2}
											<Button
												type="button"
												size="small"
												variant="secondary"
												variation="subtle"
												onclick={() => removeSampleMessage(index)}>Remove</Button
											>
										{/if}
									</div>
								{/each}
								{#if isEditable && (draft.messaging.sample_messages?.length ?? 0) < 5}
									<Button type="button" size="small" variant="secondary" onclick={addSampleMessage}
										>Add sample message</Button
									>
								{/if}
							</div>

							<Input
								id="sms-privacy-url"
								label="Privacy policy link (optional)"
								type="url"
								disabled={!isEditable}
								bind:value={draft.messaging.privacy_policy_url}
							/>
							<Input
								id="sms-terms-url"
								label="Terms link (optional)"
								type="url"
								disabled={!isEditable}
								bind:value={draft.messaging.terms_url}
							/>
							<Select
								id="sms-estimated-volume"
								label="Estimated monthly messages"
								options={estimatedVolumeOptions}
								disabled={!isEditable}
								bind:value={draft.messaging.estimated_monthly_messages}
							/>
						</div>

						{#if isEditable}
							<Checkbox
								id="sms-confirm-authorized"
								label="I confirm I am authorized to represent this business and the information above is accurate."
								checked={confirmAuthorized}
								onchange={(checked) => (confirmAuthorized = checked)}
							/>

							<div class="sms-settings__actions">
								<Button type="button" loading={saving} variant="secondary" onclick={saveDraft}
									>Save draft</Button
								>
								<Button type="button" loading={submitting} onclick={submit}
									>Submit for review</Button
								>
							</div>
						{/if}
					</form>
				</SectionBlock>
			{/if}
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.sms-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.sms-settings :global(.section-block) {
		--section-block-notch: var(--color-surface);
	}
	.sms-settings__facts {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-large);
		margin-bottom: var(--space-base);
	}
	.sms-settings__fact {
		display: grid;
		gap: var(--space-smaller);

		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}
	}
	.sms-settings__notice {
		margin: 0 0 var(--space-base);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.sms-settings__notice--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.sms-settings__error {
		margin: 0 0 var(--space-base);
		color: var(--color-critical);
	}
	.sms-settings__form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.sms-settings__group {
		display: grid;
		gap: var(--space-base);
		padding-top: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);

		&:first-child {
			padding-top: 0;
			border-top: 0;
		}

		h3 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}
	}
	.sms-settings__group-label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.sms-settings__samples {
		display: grid;
		gap: var(--space-small);
	}
	.sms-settings__sample-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);

		:global(.input) {
			flex: 1 1 auto;
		}
	}
	.sms-settings__actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 900px) {
		.sms-settings__facts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 639px) {
		.sms-settings {
			gap: var(--space-base);
		}
		.sms-settings__facts {
			grid-template-columns: minmax(0, 1fr);
		}
		.sms-settings__actions {
			justify-content: flex-start;
		}
	}
</style>
