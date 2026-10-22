<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { tick } from 'svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchSmsRegistration,
		saveSmsRegistrationDraft,
		startSmsRegistration,
		submitSmsRegistration,
		smsRegistrationKey,
		SmsRegistrationWriteError,
		type SmsRegistrationAnswers
	} from '$lib/communications/sms-registration';
	import {
		renameSmsNumber,
		setDefaultSmsNumber,
		fetchSmsCompliance,
		saveSmsCompliance,
		fetchSmsHolds,
		smsNumbersKey,
		smsComplianceKey,
		smsHoldsKey,
		SmsSettingsWriteError,
		type SmsCompliance
	} from '$lib/communications/sms-settings';
	import deviceMobileMessageIcon from '@tabler/icons/outline/device-mobile-message.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import userCheckIcon from '@tabler/icons/outline/user-check.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import checkCircleIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import infoCircleIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
	import AddNumberDialog from '$lib/components/communications/add-number/AddNumberDialog.svelte';
	import NumberReadinessCard from '$lib/components/communications/number-readiness/NumberReadinessCard.svelte';
	import ReadinessSummary from '$lib/components/communications/number-readiness/ReadinessSummary.svelte';
	import {
		fetchNumberReadiness,
		numberCard,
		numberReadinessKey,
		readinessSummary,
		type ReadinessAction
	} from '$lib/communications/number-readiness';
	import { goto } from '$app/navigation';
	import { fetchNumberCountries, numberCountriesKey } from '$lib/communications/sms-number-shop';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Add number (Stage 10 Part 2). Its country list loads when the button is pointed at, not with the page.
	let addNumberOpen = $state(false);
	function warmAddNumber() {
		void queryClient.prefetchQuery({
			queryKey: numberCountriesKey,
			queryFn: fetchNumberCountries,
			staleTime: 10 * 60_000
		});
	}
	function registerAfterBuying() {
		addNumberOpen = false;
		(
			document.getElementById('registration') ?? document.getElementById('readiness-summary-title')
		)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
	}
	const homeQuery = createQuery(() => ({
		queryKey: smsRegistrationKey,
		queryFn: fetchSmsRegistration,
		staleTime: 15_000
	}));
	// Whether each number can text yet (Stage 10 Part 4): one card per number, built from its facts.
	const readinessQuery = createQuery(() => ({
		queryKey: numberReadinessKey,
		queryFn: fetchNumberReadiness,
		staleTime: 15_000
	}));
	const cards = $derived(
		(readinessQuery.data?.numbers ?? []).map((number) =>
			numberCard(number, readinessQuery.data?.us_registration ?? null)
		)
	);
	const summary = $derived(readinessSummary(readinessQuery.data?.numbers ?? [], cards));
	let actionKey = $state<string | null>(null);

	function showBusinessDetails() {
		document.getElementById('registration')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
	}

	async function runAction(cardKey: string, action: ReadinessAction) {
		switch (action.kind) {
			case 'update_paperwork':
			case 'see_paperwork':
				await goto(
					resolve('/(app)/settings/communications/sms/paperwork/[id=uuid]', {
						id: action.paperwork_id
					})
				);
				return;
			case 'add_business_details':
				// The business details form lives on this page; a business that has none yet starts it first.
				if (!registration) {
					if (actionKey) return;
					actionKey = cardKey;
					try {
						await startSmsRegistration();
						hydratedRevision = null;
						await queryClient.invalidateQueries({ queryKey: smsRegistrationKey });
						await queryClient.invalidateQueries({ queryKey: numberReadinessKey });
					} catch (cause) {
						toast.error(
							cause instanceof Error ? cause.message : 'Your business details could not be started.'
						);
						return;
					} finally {
						actionKey = null;
					}
					await tick();
				}
				showBusinessDetails();
				return;
			default:
				showBusinessDetails();
		}
	}
	const complianceQuery = createQuery(() => ({
		queryKey: smsComplianceKey,
		queryFn: fetchSmsCompliance,
		staleTime: 15_000
	}));
	const holdsQuery = createQuery(() => ({
		queryKey: smsHoldsKey,
		queryFn: fetchSmsHolds,
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

	let draft = $state<SmsRegistrationAnswers>(emptyAnswers());
	let hydratedRevision = $state<number | null>(null);
	// Sole proprietors are the one business type Twilio lets register without an EIN/registration number, through
	// a separate "Sole Proprietor" path -- this toggle is what picks that path. Not a saved field: whether the ID
	// fields are filled in already tells the server which path applies (see smsRegistrationAnswersSchema's
	// superRefine), so this is purely local UI state that shows/hides and clears those fields.
	let hasRegistrationId = $state(true);
	const isSoleProprietorship = $derived(draft.business_type === 'sole_proprietorship');
	const showRegistrationIdFields = $derived(!isSoleProprietorship || hasRegistrationId);
	let saving = $state(false);
	let submitting = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let confirmAuthorized = $state(false);

	// Phone numbers: at most one number's name is being edited at a time.
	let renamingId = $state<string | null>(null);
	let renameDraft = $state('');
	let renameSaving = $state(false);
	let defaultSavingId = $state<string | null>(null);

	// Compliance & sender info: the form hydrates from the loaded settings exactly once, so typing doesn't
	// get clobbered by a background refetch but a save from another tab still shows up.
	function emptyCompliance(): SmsCompliance {
		return {
			opt_out_enabled: true,
			opt_out_text: null,
			sender_info_enabled: true,
			sender_info_text: null,
			periodic_reinsert_days: 30,
			updated_at: null,
			is_default: true
		};
	}
	let complianceDraft = $state<SmsCompliance>(emptyCompliance());
	let complianceHydratedAt = $state<string | null | undefined>(undefined);
	let complianceSaving = $state(false);
	let complianceError = $state('');
	let complianceFieldErrors = $state<Record<string, string>>({});

	$effect(() => {
		const compliance = complianceQuery.data?.compliance;
		if (!compliance || complianceHydratedAt === compliance.updated_at) return;
		complianceDraft = { ...compliance };
		complianceHydratedAt = compliance.updated_at;
	});

	const registration = $derived(homeQuery.data?.registration ?? null);
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
		hasRegistrationId = Boolean(saved.business_registration_id?.trim());
		hydratedRevision = registration.draft_revision;
	});

	function handleHasRegistrationIdChange(checked: boolean) {
		hasRegistrationId = checked;
		if (!checked) {
			draft.business_registration_id_type = '';
			draft.business_registration_id = '';
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

	function startRename(senderId: string, currentName: string | null) {
		renamingId = senderId;
		renameDraft = currentName ?? '';
	}
	function cancelRename() {
		renamingId = null;
		renameDraft = '';
	}
	async function saveRename() {
		if (!renamingId || renameSaving) return;
		renameSaving = true;
		try {
			await renameSmsNumber(renamingId, renameDraft);
			await queryClient.invalidateQueries({ queryKey: smsNumbersKey });
			await queryClient.invalidateQueries({ queryKey: numberReadinessKey });
			toast.success('Number name saved.');
			renamingId = null;
			renameDraft = '';
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'The number could not be renamed.');
		} finally {
			renameSaving = false;
		}
	}
	async function makeDefault(senderId: string) {
		if (defaultSavingId) return;
		defaultSavingId = senderId;
		try {
			await setDefaultSmsNumber(senderId);
			await queryClient.invalidateQueries({ queryKey: smsNumbersKey });
			await queryClient.invalidateQueries({ queryKey: numberReadinessKey });
			toast.success('Default number updated.');
		} catch (cause) {
			toast.error(
				cause instanceof Error ? cause.message : 'That number could not be made the default.'
			);
		} finally {
			defaultSavingId = null;
		}
	}

	async function saveCompliance() {
		if (complianceSaving) return;
		complianceSaving = true;
		complianceError = '';
		complianceFieldErrors = {};
		try {
			const { compliance } = await saveSmsCompliance({
				opt_out_enabled: complianceDraft.opt_out_enabled,
				opt_out_text: complianceDraft.opt_out_text,
				sender_info_enabled: complianceDraft.sender_info_enabled,
				sender_info_text: complianceDraft.sender_info_text,
				periodic_reinsert_days: complianceDraft.periodic_reinsert_days
			});
			complianceDraft = { ...compliance };
			complianceHydratedAt = compliance.updated_at;
			await queryClient.invalidateQueries({ queryKey: smsComplianceKey });
			toast.success('Compliance settings saved.');
		} catch (cause) {
			if (cause instanceof SmsSettingsWriteError) {
				complianceError = cause.message;
				complianceFieldErrors = cause.fieldErrors;
			} else
				complianceError =
					cause instanceof Error ? cause.message : 'The compliance settings could not be saved.';
		} finally {
			complianceSaving = false;
		}
	}

	function holdBadgeTone(status: string): 'success' | 'warning' | 'critical' | 'inactive' {
		return status === 'active' ? 'critical' : 'inactive';
	}
	function holdSourceLabel(source: string) {
		return source === 'platform' ? 'Platform-wide' : 'This organization';
	}

	function setOptOutText(event: Event) {
		complianceDraft.opt_out_text = (event.currentTarget as HTMLTextAreaElement).value;
	}
	function setSenderInfoText(event: Event) {
		complianceDraft.sender_info_text = (event.currentTarget as HTMLTextAreaElement).value;
	}
	function setReinsertDays(event: Event) {
		complianceDraft.periodic_reinsert_days = Number(
			(event.currentTarget as HTMLInputElement).value
		);
	}
</script>

<svelte:head><title>Phone & SMS · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="sms-settings record-detail--cards">
		<div class="sms-settings__heading">
			<Breadcrumbs
				items={[
					{ label: 'Settings', href: resolve('/(app)/settings') },
					{ label: 'Phone & SMS', icon: messageIcon }
				]}
			/>
			<PageHeader
				icon={phoneIcon}
				tone="conversation"
				title="Phone & SMS"
				description="Your texting numbers, whether each one can text yet, and what to do next."
			>
				{#snippet actions()}
					<Button
						variant="secondary"
						href={resolve('/(app)/settings/communications/sms/paperwork')}
					>
						<span aria-hidden="true">{@html fileCheckIcon}</span>
						Number paperwork
					</Button>
					<Button onclick={() => (addNumberOpen = true)} onhover={warmAddNumber}>
						<span aria-hidden="true">{@html plusIcon}</span>
						Add number
					</Button>
				{/snippet}
			</PageHeader>
		</div>

		{#if addNumberOpen}
			<AddNumberDialog
				open
				onClose={() => (addNumberOpen = false)}
				onRegister={registerAfterBuying}
			/>
		{/if}

		<div class="sms-settings__readiness" aria-busy={readinessQuery.isPending}>
			{#if readinessQuery.isPending}
				<div
					class="sms-settings__shape sms-settings__shape--summary"
					aria-label="Loading your numbers"
				></div>
				<div class="sms-settings__cards">
					{#each [0, 1] as shape (shape)}
						<div class="sms-settings__shape sms-settings__shape--card"></div>
					{/each}
				</div>
			{:else if readinessQuery.isError}
				<div class="sms-settings__state">
					<ErrorState
						title="Your numbers couldn’t load"
						description="Check your internet connection, then try again. Nothing has changed with your numbers."
						retry={() => readinessQuery.refetch()}
					/>
				</div>
			{:else if cards.length === 0}
				<div class="sms-settings__state">
					<EmptyState
						title="No texting numbers yet"
						description="Pick a number in your country and we’ll walk you through anything carriers need."
						icon={phoneIcon}
						tone="conversation"
					>
						{#snippet action()}
							<Button onclick={() => (addNumberOpen = true)} onhover={warmAddNumber}>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
								<span aria-hidden="true">{@html plusIcon}</span>
								Add number
							</Button>
						{/snippet}
					</EmptyState>
				</div>
			{:else}
				<ReadinessSummary {summary} {cards} />
				<div class="sms-settings__cards">
					{#each cards as card (card.key)}
						<NumberReadinessCard
							{card}
							renaming={renamingId !== null && renamingId === card.sender_id}
							{renameSaving}
							defaultSaving={defaultSavingId === card.sender_id}
							actionLoading={actionKey === card.key}
							bind:renameDraft
							onStartRename={() => card.sender_id && startRename(card.sender_id, card.display_name)}
							onCancelRename={cancelRename}
							onSaveRename={saveRename}
							onMakeDefault={() => card.sender_id && makeDefault(card.sender_id)}
							onAction={(action) => runAction(card.key, action)}
						/>
					{/each}
				</div>
				<p class="sms-settings__foot">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
					<span aria-hidden="true">{@html infoCircleIcon}</span>
					Rename a number or make it your default from its ⋯ menu. To release a number, contact us.
				</p>
			{/if}
		</div>

		{#if homeQuery.isPending}
			<LoadingSkeleton variant="card" rows={3} />
		{:else if homeQuery.isError}
			<ErrorState
				description="Phone & SMS could not be loaded."
				retry={() => homeQuery.refetch()}
			/>
		{:else}
			{#if registration}
				<SectionBlock
					tone="inactive"
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
							<div class="sms-settings__group-head">
								<span class="sms-settings__group-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									{@html buildingIcon}
								</span>
								<h3>Business identity</h3>
							</div>
							<div class="sms-settings__fields">
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
								{#if showRegistrationIdFields}
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
								{/if}
								{#if isSoleProprietorship}
									<div class="sms-settings__field--full">
										<Toggle
											id="sms-has-registration-id"
											label="I have a business registration number (EIN)"
											description="Turn this off if you run the business under your own name with no registered
												company and no EIN. You'll register as a sole proprietor instead, which Twilio
												verifies with a text to your own phone rather than a registration number."
											checked={hasRegistrationId}
											disabled={!isEditable}
											onchange={handleHasRegistrationIdChange}
										/>
									</div>
								{/if}
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
						</div>

						<div class="sms-settings__group">
							<div class="sms-settings__group-head">
								<span class="sms-settings__group-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									{@html mapPinIcon}
								</span>
								<h3>Business address</h3>
							</div>
							<div class="sms-settings__fields">
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
								<CountryPicker
									id="sms-address-country"
									label="Country"
									disabled={!isEditable}
									bind:value={draft.business_address.country_code}
								/>
							</div>
							{#if isSoleProprietorship && !hasRegistrationId}
								<p class="sms-settings__hint">
									Sole proprietors with no registration number must use a US or Canada address --
									choose United States or Canada here.
								</p>
							{/if}
						</div>

						<div class="sms-settings__group">
							<div class="sms-settings__group-head">
								<span class="sms-settings__group-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									{@html userCheckIcon}
								</span>
								<h3>Authorized representative</h3>
							</div>
							<div class="sms-settings__fields">
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
						</div>

						<div class="sms-settings__group">
							<div class="sms-settings__group-head">
								<span class="sms-settings__group-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									{@html messageIcon}
								</span>
								<h3>Messaging</h3>
							</div>
							<div class="sms-settings__messaging">
								<div class="sms-settings__messaging-col">
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
								</div>
								<div class="sms-settings__messaging-col">
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
											<Button
												type="button"
												size="small"
												variant="secondary"
												onclick={addSampleMessage}>Add sample message</Button
											>
										{/if}
									</div>
									<div class="sms-settings__links">
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
									</div>
									<Select
										id="sms-estimated-volume"
										label="Estimated monthly messages"
										options={estimatedVolumeOptions}
										disabled={!isEditable}
										bind:value={draft.messaging.estimated_monthly_messages}
									/>
								</div>
							</div>
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

			<div class="sms-settings__lower">
				<SectionBlock tone="inactive" title="Holds & opt-outs" icon={banIcon} level={2}>
					{#if holdsQuery.isPending}
						<LoadingSkeleton variant="card" rows={2} />
					{:else if holdsQuery.isError}
						<ErrorState
							description="Holds and opt-outs could not be loaded."
							retry={() => holdsQuery.refetch()}
						/>
					{:else}
						<div class="sms-settings__tiles">
							<div class="sms-settings__tile">
								<span>Customers opted out</span>
								<strong>{holdsQuery.data.opt_outs.total}</strong>
							</div>
							<div class="sms-settings__tile">
								<span>Active holds</span>
								<strong>{holdsQuery.data.holds.length}</strong>
							</div>
						</div>
						{#if !holdsQuery.data.holds.length}
							<p
								class="sms-settings__notice sms-settings__notice--success sms-settings__notice--icon"
								role="status"
							>
								<span class="sms-settings__notice-icon" aria-hidden="true">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
									{@html checkCircleIcon}
								</span>
								No active holds. Sending is not paused for any reason right now.
							</p>
						{:else}
							<ul class="sms-settings__numbers">
								{#each holdsQuery.data.holds as hold (hold.id)}
									<li class="sms-settings__number-row">
										<div class="sms-settings__number-main">
											<div class="sms-settings__number-identity">
												<strong>{hold.reason}</strong>
												<span
													>{holdSourceLabel(hold.source)} · placed {new Date(
														hold.placed_at
													).toLocaleDateString()}</span
												>
											</div>
											<div class="sms-settings__number-badges">
												<StatusBadge status={holdBadgeTone(hold.status)}
													>{hold.status === 'active' ? 'Active' : hold.status}</StatusBadge
												>
											</div>
										</div>
									</li>
								{/each}
							</ul>
							<p class="sms-settings__notice" role="status">
								Holds are released by Jafar or the provider, never directly by a contractor. Contact
								Jafar if a hold needs review.
							</p>
						{/if}
					{/if}
				</SectionBlock>

				<SectionBlock
					tone="inactive"
					title="Compliance & sender info"
					icon={shieldCheckIcon}
					level={2}
				>
					{#if complianceQuery.isPending}
						<LoadingSkeleton variant="card" rows={2} />
					{:else if complianceQuery.isError}
						<ErrorState
							description="The compliance settings could not be loaded."
							retry={() => complianceQuery.refetch()}
						/>
					{:else}
						{#if complianceError}<p class="sms-settings__error" role="alert">
								{complianceError}
							</p>{/if}
						<div class="sms-settings__form">
							<div class="sms-settings__group">
								<Toggle
									id="sms-compliance-opt-out"
									label="Add opt-out instructions to outbound texts"
									description="Appends wording like “Reply STOP to unsubscribe” so customers can opt out."
									labelSide="start"
									bind:checked={complianceDraft.opt_out_enabled}
								/>
								<Textarea
									id="sms-compliance-opt-out-text"
									label="Custom opt-out wording (optional)"
									rows={2}
									maxlength={320}
									disabled={!complianceDraft.opt_out_enabled}
									value={complianceDraft.opt_out_text ?? ''}
									oninput={setOptOutText}
									invalid={Boolean(complianceFieldErrors.opt_out_text)}
									errorMessage={complianceFieldErrors.opt_out_text}
								/>
							</div>
							<div class="sms-settings__group">
								<Toggle
									id="sms-compliance-sender-info"
									label="Identify the business in outbound texts"
									description="Appends your business name so customers know who is texting them."
									labelSide="start"
									bind:checked={complianceDraft.sender_info_enabled}
								/>
								<Textarea
									id="sms-compliance-sender-info-text"
									label="Custom sender wording (optional)"
									rows={2}
									maxlength={320}
									disabled={!complianceDraft.sender_info_enabled}
									value={complianceDraft.sender_info_text ?? ''}
									oninput={setSenderInfoText}
									invalid={Boolean(complianceFieldErrors.sender_info_text)}
									errorMessage={complianceFieldErrors.sender_info_text}
								/>
							</div>
							<div class="sms-settings__group">
								<Input
									id="sms-compliance-reinsert-days"
									label="Re-add opt-out/sender wording every (days)"
									type="number"
									min={1}
									max={60}
									value={complianceDraft.periodic_reinsert_days}
									oninput={setReinsertDays}
									invalid={Boolean(complianceFieldErrors.periodic_reinsert_days)}
									errorMessage={complianceFieldErrors.periodic_reinsert_days}
									class="sms-settings__field-days"
								/>
							</div>
							<div class="sms-settings__actions">
								<Button type="button" loading={complianceSaving} onclick={saveCompliance}
									>Save compliance settings</Button
								>
							</div>
						</div>
					{/if}
				</SectionBlock>
			</div>
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.sms-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	/* App-look cards: each block is a white card on the app background. The shared card rules (the
	   `record-detail--cards` context) put the heading and actions inside the card header; the page only
	   restores the framed icon tile and the spacing the approved frame shows. */
	.sms-settings.record-detail--cards :global(.section-block) :global(.section-block__title) {
		gap: var(--space-slim);
	}
	/* Page header: a 60px blue tile beside the breadcrumb, 36px title and sentence, as in the approved frame. */

	/* The page's own gap already spaces the header from the summary. */
	.sms-settings__heading :global(.page-header) {
		margin-bottom: 0;
	}
	/* Number readiness (Stage 10 Part 4, board NbWfA): the summary, the number cards two to a row, one foot line. */
	.sms-settings__readiness {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	.sms-settings__cards {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-large);
		align-items: stretch;
	}
	.sms-settings__state {
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
	}
	.sms-settings__shape {
		border-radius: var(--radius-large);
		background: linear-gradient(
			90deg,
			var(--color-border),
			var(--color-surface--background--subtle),
			var(--color-border)
		);
		background-size: 200% 100%;
		animation: sms-settings-shimmer 1.4s ease-in-out infinite;

		&--summary {
			height: 200px;
		}
		&--card {
			height: 300px;
		}
	}
	@keyframes sms-settings-shimmer {
		to {
			background-position: -200% 0;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.sms-settings__shape {
			animation: none;
		}
	}
	.sms-settings__foot {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 500;

		:global(svg) {
			width: 14px;
			height: 14px;
			color: var(--color-informative);
		}
	}
	.sms-settings__tiles {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin-bottom: var(--space-base);
	}
	.sms-settings__tile {
		display: grid;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);

		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			line-height: var(--typography--lineHeight-tight);
		}
	}
	.sms-settings__notice {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
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
	.sms-settings__notice--success {
		color: var(--color-text);
		background: var(--color-surface--background--subtle);
	}
	.sms-settings__notice--success .sms-settings__notice-icon {
		color: var(--color-success);
	}
	.sms-settings__notice-icon {
		display: inline-flex;
		flex: 0 0 auto;
	}
	.sms-settings__notice-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
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
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding-top: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);

		&:first-child {
			padding-top: 0;
			border-top: 0;
		}
	}
	.sms-settings__group-head {
		display: flex;
		align-items: center;
		gap: var(--space-small);

		h3 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			line-height: var(--typography--lineHeight-base);
		}
	}
	.sms-settings__group-icon {
		display: inline-flex;
		color: var(--color-icon--secondary);
	}
	.sms-settings__group-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	.sms-settings__fields {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.sms-settings__field--full {
		grid-column: 1 / -1;
	}
	.sms-settings__messaging {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-large);
		align-items: start;
	}
	.sms-settings__messaging-col {
		display: grid;
		gap: var(--space-base);
		align-content: start;
		min-width: 0;
	}
	.sms-settings__links {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.sms-settings__group-label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.sms-settings__hint {
		margin: calc(var(--space-small) * -1) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	/* The re-add-days field reads best short, as drawn in the approved frame. */
	.sms-settings :global(.sms-settings__field-days) {
		max-width: 14rem;
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

	/* Lower area: phone numbers + holds stacked on the left, compliance on the right. */
	.sms-settings__lower {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
		gap: var(--space-large);
		align-items: start;
	}
	/* The holds list rows. */
	.sms-settings__numbers {
		display: grid;
		gap: var(--space-small);
		margin: 0 0 var(--space-base);
		padding: 0;
		list-style: none;
	}
	.sms-settings__number-row {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-start;
		gap: 12px;
		padding: 14px 16px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.sms-settings__number-main {
		display: grid;
		flex: 1 1 0;
		align-content: start;
		gap: 8px;
		min-width: 12rem;
	}
	.sms-settings__number-identity {
		display: grid;
		gap: 2px;
		min-width: 0;

		strong {
			color: var(--color-heading);
		}
		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
	.sms-settings__number-badges {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	@media (max-width: 900px) {
		.sms-settings__cards,
		.sms-settings__messaging,
		.sms-settings__lower {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 639px) {
		.sms-settings {
			gap: var(--space-base);
		}
		.sms-settings__tiles,
		.sms-settings__fields,
		.sms-settings__links {
			grid-template-columns: minmax(0, 1fr);
		}
		.sms-settings__actions {
			justify-content: flex-start;
		}
	}
</style>
