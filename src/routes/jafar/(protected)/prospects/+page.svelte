<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';

	const queryClient = useQueryClient();

	type ProspectStage =
		| 'new'
		| 'awaiting_payment'
		| 'payment_confirmed'
		| 'needs_attention'
		| 'account_created'
		| 'not_proceeding';
	type JsonRecord = Record<string, unknown>;
	type ProspectSummary = {
		id: string;
		stage: ProspectStage;
		business_name: string;
		main_contact_name: string;
		main_contact_email: string;
		main_contact_phone: string;
		trade: string;
		city_country: string;
		time_zone: string;
		package_version_id: string;
		package_snapshot: unknown;
		possible_duplicate: boolean;
		submitted_at: string;
		updated_at: string;
		not_proceeding_at: string | null;
	};
	type ProspectDetail = ProspectSummary & {
		initial_administrator_name: string | null;
		initial_administrator_email: string | null;
		note: string | null;
		personal_data_purge_after: string;
	};
	type OriginalSubmission = {
		id: string;
		submitted_data: unknown;
		package_snapshot: unknown;
		privacy_policy_version: string;
		agreement_accepted_at: string;
		submitted_at: string;
	};
	type Correction = {
		id: string;
		actor_owner_email: string;
		reason: string;
		before_state: unknown;
		after_state: unknown;
		created_at: string;
	};
	type SetupLink = {
		intended_email: string;
		expires_at: string;
		consumed_at: string | null;
		last_sent_at: string;
		last_error: string | null;
	};
	type ProspectListResponse = { prospects: ProspectSummary[]; error?: string };
	type ProspectDetailResponse = {
		prospect: ProspectDetail;
		original_submission: OriginalSubmission | null;
		corrections: Correction[];
		setup_link: SetupLink | null;
		error?: string;
	};

	const stages: { value: string; label: string }[] = [
		{ value: '', label: 'All stages' },
		{ value: 'new', label: 'New' },
		{ value: 'awaiting_payment', label: 'Awaiting payment' },
		{ value: 'payment_confirmed', label: 'Payment confirmed' },
		{ value: 'needs_attention', label: 'Needs attention' },
		{ value: 'account_created', label: 'Account created' },
		{ value: 'not_proceeding', label: 'Not proceeding' }
	];

	type CorrectionForm = {
		business_name: string;
		main_contact_name: string;
		main_contact_email: string;
		main_contact_phone: string;
		initial_administrator_name: string;
		initial_administrator_email: string;
		trade: string;
		city_country: string;
		time_zone: string;
		note: string;
		reason: string;
	};
	type PaymentConfirmationForm = {
		amountDollars: string;
		private_reference: string;
		mismatch_reason: string;
	};
	type ActionResponse = { ok?: boolean; error?: string };

	const correctableStages: ProspectStage[] = [
		'new',
		'awaiting_payment',
		'payment_confirmed',
		'needs_attention'
	];
	const unpaidStages: ProspectStage[] = ['new', 'awaiting_payment', 'needs_attention'];
	const provisionableStages: ProspectStage[] = ['payment_confirmed', 'needs_attention'];

	let search = $state('');
	let stageFilter = $state('');
	let selectedProspectId = $state<string | null>(null);
	let editingCorrection = $state(false);
	let confirmingNotProceeding = $state(false);
	let confirmingPayment = $state(false);
	let confirmingProvision = $state(false);
	let correctionForm = $state<CorrectionForm>(emptyCorrectionForm());
	let paymentForm = $state<PaymentConfirmationForm>(emptyPaymentForm());
	let actionError = $state('');
	let actionMessage = $state('');

	function emptyCorrectionForm(): CorrectionForm {
		return {
			business_name: '',
			main_contact_name: '',
			main_contact_email: '',
			main_contact_phone: '',
			initial_administrator_name: '',
			initial_administrator_email: '',
			trade: '',
			city_country: '',
			time_zone: '',
			note: '',
			reason: ''
		};
	}

	function emptyPaymentForm(): PaymentConfirmationForm {
		return { amountDollars: '', private_reference: '', mismatch_reason: '' };
	}

	function clearFeedback() {
		actionError = '';
		actionMessage = '';
	}

	function openCorrectionForm(detail: ProspectDetail) {
		clearFeedback();
		confirmingNotProceeding = false;
		confirmingPayment = false;
		confirmingProvision = false;
		correctionForm = {
			business_name: detail.business_name,
			main_contact_name: detail.main_contact_name,
			main_contact_email: detail.main_contact_email,
			main_contact_phone: detail.main_contact_phone,
			initial_administrator_name: detail.initial_administrator_name ?? '',
			initial_administrator_email: detail.initial_administrator_email ?? '',
			trade: detail.trade,
			city_country: detail.city_country,
			time_zone: detail.time_zone,
			note: detail.note ?? '',
			reason: ''
		};
		editingCorrection = true;
	}

	function openPaymentForm() {
		clearFeedback();
		editingCorrection = false;
		confirmingNotProceeding = false;
		confirmingProvision = false;
		paymentForm = emptyPaymentForm();
		confirmingPayment = true;
	}

	function openProvisionConfirm() {
		clearFeedback();
		editingCorrection = false;
		confirmingNotProceeding = false;
		confirmingPayment = false;
		confirmingProvision = true;
	}

	function administratorEmail(detail: ProspectDetail) {
		return detail.initial_administrator_email ?? detail.main_contact_email;
	}

	const prospects = createQuery<ProspectListResponse>(() => ({
		queryKey: ['jafar', 'prospects', stageFilter, search],
		queryFn: async () => {
			const params = new URLSearchParams();
			if (stageFilter) params.set('stage', stageFilter);
			if (search.trim()) params.set('search', search.trim());
			const query = params.toString();
			const response = await fetch(`/api/jafar/prospects${query ? `?${query}` : ''}`);
			const result = (await response.json()) as ProspectListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Prospects could not be loaded.');
			return result;
		}
	}));

	const prospectDetail = createQuery<ProspectDetailResponse>(() => ({
		queryKey: ['jafar', 'prospect', selectedProspectId],
		enabled: Boolean(selectedProspectId),
		queryFn: async () => {
			if (!selectedProspectId) throw new Error('Choose a prospect first.');
			const response = await fetch(`/api/jafar/prospects/${selectedProspectId}`);
			const result = (await response.json()) as ProspectDetailResponse;
			if (!response.ok) throw new Error(result.error ?? 'Prospect could not be loaded.');
			return result;
		}
	}));

	const prospectList = $derived(prospects.data?.prospects ?? []);
	const attentionCount = $derived(
		prospectList.filter((prospect) => prospect.stage === 'needs_attention').length
	);
	const paymentCount = $derived(
		prospectList.filter((prospect) => prospect.stage === 'awaiting_payment').length
	);
	const duplicateCount = $derived(
		prospectList.filter((prospect) => prospect.possible_duplicate).length
	);

	const correctProspect = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedProspectId) throw new Error('Choose a prospect first.');
			const response = await fetch(`/api/jafar/prospects/${selectedProspectId}/correct`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					...correctionForm,
					initial_administrator_name: correctionForm.initial_administrator_name || null,
					initial_administrator_email: correctionForm.initial_administrator_email || null,
					note: correctionForm.note || null
				})
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok) throw new Error(result.error ?? 'The correction could not be saved.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			editingCorrection = false;
			actionMessage = 'Correction saved.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospects'] });
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospect', selectedProspectId] });
		}
	}));

	const markNotProceeding = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedProspectId) throw new Error('Choose a prospect first.');
			const response = await fetch(`/api/jafar/prospects/${selectedProspectId}/not-proceeding`, {
				method: 'POST'
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok) throw new Error(result.error ?? 'The application could not be updated.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			confirmingNotProceeding = false;
			actionMessage = 'Application marked not proceeding.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospects'] });
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospect', selectedProspectId] });
		}
	}));

	const confirmPayment = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedProspectId) throw new Error('Choose a prospect first.');
			const amountCents = Math.round(Number(paymentForm.amountDollars) * 100);
			const response = await fetch(`/api/jafar/prospects/${selectedProspectId}/confirm-payment`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					amount_usd_cents: amountCents,
					private_reference: paymentForm.private_reference,
					mismatch_reason: paymentForm.mismatch_reason || null
				})
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok) throw new Error(result.error ?? 'The payment could not be confirmed.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			confirmingPayment = false;
			actionMessage = 'Payment confirmed.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospects'] });
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospect', selectedProspectId] });
		}
	}));

	const provisionOrganization = createMutation<
		ActionResponse & { setup_email_sent?: boolean },
		Error,
		void
	>(() => ({
		mutationFn: async () => {
			if (!selectedProspectId) throw new Error('Choose a prospect first.');
			const response = await fetch(`/api/jafar/prospects/${selectedProspectId}/provision`, {
				method: 'POST'
			});
			const result = (await response.json()) as ActionResponse & { setup_email_sent?: boolean };
			if (!response.ok)
				throw new Error(result.error ?? 'The organization could not be provisioned.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: (result) => {
			confirmingProvision = false;
			actionMessage =
				result.setup_email_sent === false
					? 'Organization provisioned, but the setup email could not be sent. Resend it below.'
					: 'Organization provisioned. Setup email sent.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospects'] });
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospect', selectedProspectId] });
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
		}
	}));

	const resendSetupEmail = createMutation<ActionResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!selectedProspectId) throw new Error('Choose a prospect first.');
			const response = await fetch(`/api/jafar/prospects/${selectedProspectId}/send-setup-email`, {
				method: 'POST'
			});
			const result = (await response.json()) as ActionResponse;
			if (!response.ok) throw new Error(result.error ?? 'The setup email could not be sent.');
			return result;
		},
		onMutate: () => clearFeedback(),
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			actionMessage = 'Setup email sent.';
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'prospect', selectedProspectId] });
		}
	}));

	function clearFilters() {
		search = '';
		stageFilter = '';
		selectedProspectId = null;
	}

	function clearSelection() {
		selectedProspectId = null;
		editingCorrection = false;
		confirmingNotProceeding = false;
		confirmingPayment = false;
		confirmingProvision = false;
		clearFeedback();
	}

	function selectProspect(id: string) {
		selectedProspectId = id;
		editingCorrection = false;
		confirmingNotProceeding = false;
		confirmingPayment = false;
		confirmingProvision = false;
		clearFeedback();
	}

	function handleProspectRowKeydown(event: KeyboardEvent, id: string) {
		if (event.key !== 'Enter' && event.key !== ' ') return;
		event.preventDefault();
		selectProspect(id);
	}

	function formatDate(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: '—';
	}

	function stageLabel(stage: ProspectStage) {
		return stages.find((option) => option.value === stage)?.label ?? stage;
	}

	function stageTone(stage: ProspectStage) {
		return stage === 'account_created'
			? 'success'
			: stage === 'needs_attention' || stage === 'not_proceeding'
				? 'critical'
				: stage === 'payment_confirmed'
					? 'informative'
					: stage === 'awaiting_payment'
						? 'warning'
						: 'inactive';
	}

	function asRecord(value: unknown): JsonRecord | null {
		return typeof value === 'object' && value !== null && !Array.isArray(value)
			? (value as JsonRecord)
			: null;
	}

	function textValue(value: unknown, fallback = '—') {
		return typeof value === 'string' || typeof value === 'number' ? String(value) : fallback;
	}

	function packageName(snapshot: unknown) {
		const record = asRecord(snapshot);
		return textValue(record?.display_name ?? record?.package_name ?? record?.package_key);
	}

	function packagePriceCents(snapshot: unknown) {
		const record = asRecord(snapshot);
		const cents = record?.price_usd_cents;
		return typeof cents === 'number' ? cents : null;
	}

	function packagePrice(snapshot: unknown) {
		const cents = packagePriceCents(snapshot);
		if (cents === null) return 'Price not recorded';
		const record = asRecord(snapshot);
		return new Intl.NumberFormat(undefined, {
			style: 'currency',
			currency: textValue(record?.currency, 'USD')
		}).format(cents / 100);
	}

	function paymentAmountMismatches(detail: ProspectDetail) {
		const listedCents = packagePriceCents(detail.package_snapshot);
		const enteredDollars = Number(paymentForm.amountDollars);
		if (listedCents === null || !paymentForm.amountDollars || Number.isNaN(enteredDollars))
			return false;
		return Math.round(enteredDollars * 100) !== listedCents;
	}

	function jsonPreview(value: unknown) {
		return JSON.stringify(value, null, 2);
	}
</script>

<svelte:head>
	<title>Prospects · Control Room</title>
</svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="prospects">
	<header class="prospects__header">
		<div>
			<p class="prospects__eyebrow">Onboarding queue</p>
			<h1>Prospects</h1>
			<p class="prospects__description">
				Review onboarding applications before they become contractor workspaces.
			</p>
		</div>
	</header>

	<section class="prospects__summary" aria-label="Prospect summary">
		<KpiCard
			label="All prospects"
			value={String(prospectList.length)}
			note="Current results"
			icon={usersIcon}
			variant="compact"
		/>
		<KpiCard
			label="Need attention"
			value={String(attentionCount)}
			note="Review before provisioning"
			icon={alertIcon}
			tone="warning"
			variant="compact"
		/>
		<KpiCard
			label="Awaiting payment"
			value={String(paymentCount)}
			note="Payment not confirmed"
			icon={checkIcon}
			tone="informative"
			variant="compact"
		/>
		<KpiCard
			label="Possible duplicates"
			value={String(duplicateCount)}
			note="Compare before proceeding"
			icon={alertIcon}
			tone="critical"
			variant="compact"
		/>
	</section>

	<section class="prospects__filters" aria-label="Prospect filters">
		<div class="prospects__filter-field prospects__filter-field--search">
			<label for="prospect-search">Search applications</label>
			<SearchInput
				id="prospect-search"
				bind:value={search}
				placeholder="Search business or administrator"
				ariaLabel="Search applications"
			/>
		</div>
		<div class="prospects__filter-field">
			<label for="prospect-stage">Stage</label>
			<Select
				id="prospect-stage"
				bind:value={stageFilter}
				options={stages}
				ariaLabel="Filter prospects by stage"
				onchange={clearSelection}
			/>
		</div>
		<Button type="button" variant="secondary" variation="subtle" size="small" onclick={clearFilters}
			>Clear filters</Button
		>
	</section>

	<div class="prospects__list-meta" aria-live="polite">
		<span><strong>{prospectList.length}</strong> prospects shown</span>
		<span>Updated from the onboarding queue</span>
	</div>

	<section class="prospects__table-panel" aria-labelledby="prospect-list-title">
		<h2 id="prospect-list-title" class="prospects__sr-only">Prospect list</h2>
		{#if prospects.isPending}
			<div class="prospects__state">
				<LoadingSkeleton variant="table" rows={5} label="Loading prospects" />
			</div>
		{:else if prospects.isError}
			<div class="prospects__state">
				<ErrorState
					title="Prospects could not be loaded"
					description={prospects.error.message}
					retry={() => prospects.refetch()}
				/>
			</div>
		{:else if prospectList.length === 0}
			<div class="prospects__state">
				<EmptyState
					title="No matching prospects"
					description="Try another search or stage filter."
				/>
			</div>
		{:else}
			<div class="prospects__table-wrap">
				<table>
					<thead>
						<tr>
							<th scope="col">Business</th>
							<th scope="col">Package snapshot</th>
							<th scope="col">Stage</th>
							<th scope="col">Submitted</th>
							<th scope="col"><span class="prospects__sr-only">Open review</span></th>
						</tr>
					</thead>
					<tbody>
						{#each prospectList as prospect (prospect.id)}
							<tr
								class={[
									'prospects__table-row',
									selectedProspectId === prospect.id && 'prospects__table-row--selected'
								]}
								tabindex="0"
								aria-label={`Review ${prospect.business_name}`}
								aria-selected={selectedProspectId === prospect.id}
								onclick={() => selectProspect(prospect.id)}
								onkeydown={(event) => handleProspectRowKeydown(event, prospect.id)}
							>
								<th scope="row">
									<strong>{prospect.business_name}</strong>
									<small>{prospect.main_contact_name} · {prospect.main_contact_email}</small>
									<small>{prospect.trade} · {prospect.city_country}</small>
								</th>
								<td>
									<strong>{packageName(prospect.package_snapshot)}</strong>
									<small>{packagePrice(prospect.package_snapshot)} monthly snapshot</small>
								</td>
								<td>
									<Badge status={stageTone(prospect.stage)}>{stageLabel(prospect.stage)}</Badge>
									{#if prospect.possible_duplicate}
										<small class="prospects__warning-label">
											<span aria-hidden="true">{@html alertIcon}</span>
											Duplicate check
										</small>
									{/if}
								</td>
								<td>{formatDate(prospect.submitted_at)}</td>
								<td>
									<span class="prospects__row-action" aria-hidden="true">
										{@html arrowRightIcon}
									</span>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
		<footer class="prospects__table-footer">
			<span>Possible duplicate is a review warning, not a separate stage.</span>
			{#if selectedProspectId}
				<button class="prospects__quiet-button" type="button" onclick={clearSelection}
					>Close review</button
				>
			{/if}
		</footer>
	</section>

	{#if selectedProspectId}
		<section class="prospects__review" aria-labelledby="prospect-review-title">
			{#if prospectDetail.isPending}
				<div class="prospects__review-state">
					<LoadingSkeleton variant="card" label="Loading prospect review" />
				</div>
			{:else if prospectDetail.isError}
				<div class="prospects__review-state">
					<ErrorState
						title="Prospect review could not be loaded"
						description={prospectDetail.error.message}
						retry={() => prospectDetail.refetch()}
					/>
				</div>
			{:else if prospectDetail.data}
				{@const detail = prospectDetail.data.prospect}
				<div class="prospects__review-icon" aria-hidden="true">{@html checkIcon}</div>
				<div class="prospects__review-content">
					<p class="prospects__eyebrow">Selected review</p>
					<div class="prospects__review-heading">
						<h2 id="prospect-review-title">{detail.business_name}</h2>
						<Badge status={stageTone(detail.stage)}>{stageLabel(detail.stage)}</Badge>
					</div>
					<p>
						{#if detail.possible_duplicate}
							This application may duplicate an existing organization. Compare it before creating an
							account.
						{:else}
							Review the application, contact details, and selected package before the next
							onboarding step.
						{/if}
					</p>
					<dl class="prospects__review-details">
						<div>
							<dt>Primary contact</dt>
							<dd>{detail.main_contact_name}</dd>
						</div>
						<div>
							<dt>Email</dt>
							<dd>{detail.main_contact_email}</dd>
						</div>
						<div>
							<dt>Package</dt>
							<dd>
								{packageName(detail.package_snapshot)} · {packagePrice(detail.package_snapshot)}
							</dd>
						</div>
						<div>
							<dt>Submitted</dt>
							<dd>{formatDate(detail.submitted_at)}</dd>
						</div>
					</dl>
					{#if actionMessage}<p
							class="prospects__feedback prospects__feedback--success"
							role="status"
						>
							{actionMessage}
						</p>{/if}
					{#if actionError}<p class="prospects__feedback prospects__feedback--error" role="alert">
							{actionError}
						</p>{/if}

					{#if correctableStages.includes(detail.stage) || unpaidStages.includes(detail.stage)}
						<div class="prospects__owner-actions">
							{#if correctableStages.includes(detail.stage)}
								<Button
									type="button"
									variant="tertiary"
									disabled={editingCorrection}
									onclick={() => openCorrectionForm(detail)}>Correct details</Button
								>
							{/if}
							{#if unpaidStages.includes(detail.stage)}
								<Button
									type="button"
									variant="tertiary"
									disabled={confirmingPayment}
									onclick={openPaymentForm}>Confirm payment</Button
								>
								<Button
									type="button"
									variant="tertiary"
									disabled={confirmingNotProceeding}
									onclick={() => {
										clearFeedback();
										editingCorrection = false;
										confirmingPayment = false;
										confirmingProvision = false;
										confirmingNotProceeding = true;
									}}>Mark not proceeding</Button
								>
							{/if}
							{#if provisionableStages.includes(detail.stage)}
								<Button type="button" disabled={confirmingProvision} onclick={openProvisionConfirm}
									>Provision organization</Button
								>
							{/if}
						</div>
					{/if}

					{#if detail.stage === 'account_created'}
						{@const setupLink = prospectDetail.data.setup_link}
						<div class="prospects__setup-status">
							{#if setupLink?.consumed_at}
								<p>
									<span aria-hidden="true">{@html checkIcon}</span>
									The administrator ({setupLink.intended_email}) has set their password.
								</p>
							{:else if setupLink}
								<p>
									<span aria-hidden="true">{@html checkIcon}</span>
									Setup email sent to <strong>{setupLink.intended_email}</strong> on {formatDate(
										setupLink.last_sent_at
									)}, expires {formatDate(setupLink.expires_at)}.
									{#if setupLink.last_error}
										<span class="prospects__setup-status-error"
											>Last attempt failed: {setupLink.last_error}</span
										>
									{/if}
								</p>
								<Button
									type="button"
									variant="tertiary"
									size="small"
									loading={resendSetupEmail.isPending}
									onclick={() => resendSetupEmail.mutate()}>Resend setup email</Button
								>
							{:else}
								<p>
									<span aria-hidden="true">{@html alertIcon}</span>
									No setup email has been sent yet.
								</p>
								<Button
									type="button"
									variant="tertiary"
									size="small"
									loading={resendSetupEmail.isPending}
									onclick={() => resendSetupEmail.mutate()}>Send setup email</Button
								>
							{/if}
						</div>
					{/if}

					{#if editingCorrection}
						<form
							class="prospects__correction-form"
							onsubmit={(event) => {
								event.preventDefault();
								correctProspect.mutate();
							}}
						>
							<div class="prospects__form-grid">
								<label
									><span>Business name</span><input
										bind:value={correctionForm.business_name}
										required
										maxlength="160"
									/></label
								>
								<label
									><span>Trade</span><input
										bind:value={correctionForm.trade}
										required
										maxlength="120"
									/></label
								>
								<label
									><span>Main contact name</span><input
										bind:value={correctionForm.main_contact_name}
										required
										maxlength="160"
									/></label
								>
								<label
									><span>Main contact email</span><input
										bind:value={correctionForm.main_contact_email}
										type="email"
										required
										maxlength="254"
									/></label
								>
								<label
									><span>Main contact phone</span><input
										bind:value={correctionForm.main_contact_phone}
										required
										maxlength="40"
									/></label
								>
								<label
									><span>City / country</span><input
										bind:value={correctionForm.city_country}
										required
										maxlength="160"
									/></label
								>
								<label
									><span>Time zone</span><input
										bind:value={correctionForm.time_zone}
										required
										maxlength="64"
									/></label
								>
								<label
									><span>Administrator name (optional)</span><input
										bind:value={correctionForm.initial_administrator_name}
										maxlength="160"
									/></label
								>
								<label
									><span>Administrator email (optional)</span><input
										bind:value={correctionForm.initial_administrator_email}
										type="email"
										maxlength="254"
									/></label
								>
								<label class="prospects__form-wide"
									><span>Applicant note (optional)</span><textarea
										bind:value={correctionForm.note}
										maxlength="2000"></textarea></label
								>
								<label class="prospects__form-wide"
									><span>Private reason for this correction</span><textarea
										bind:value={correctionForm.reason}
										required
										maxlength="500"></textarea></label
								>
							</div>
							<div class="prospects__form-actions">
								<Button
									type="button"
									variant="secondary"
									variation="subtle"
									disabled={correctProspect.isPending}
									onclick={() => (editingCorrection = false)}>Cancel</Button
								>
								<Button type="submit" loading={correctProspect.isPending}>Save correction</Button>
							</div>
						</form>
					{/if}

					{#if confirmingPayment}
						<form
							class="prospects__correction-form"
							onsubmit={(event) => {
								event.preventDefault();
								confirmPayment.mutate();
							}}
						>
							<p class="prospects__payment-price-note">
								Package price on file: <strong>{packagePrice(detail.package_snapshot)}</strong>
							</p>
							<div class="prospects__form-grid">
								<label
									><span>Amount received (USD)</span><input
										bind:value={paymentForm.amountDollars}
										type="number"
										step="0.01"
										min="0.01"
										required
									/></label
								>
								<label
									><span>Private payment reference</span><input
										bind:value={paymentForm.private_reference}
										required
										maxlength="240"
									/></label
								>
								{#if paymentAmountMismatches(detail)}
									<label class="prospects__form-wide"
										><span>Reason the amount differs from the package price</span><textarea
											bind:value={paymentForm.mismatch_reason}
											required
											maxlength="500"></textarea></label
									>
								{/if}
							</div>
							<div class="prospects__form-actions">
								<Button
									type="button"
									variant="secondary"
									variation="subtle"
									disabled={confirmPayment.isPending}
									onclick={() => (confirmingPayment = false)}>Cancel</Button
								>
								<Button type="submit" loading={confirmPayment.isPending}>Confirm payment</Button>
							</div>
						</form>
					{/if}

					{#if confirmingNotProceeding}
						<div class="prospects__not-proceeding-confirm" role="alertdialog" aria-live="assertive">
							<span aria-hidden="true">{@html alertIcon}</span>
							<p>
								This marks the application as not proceeding. It can no longer be corrected,
								confirmed for payment, or provisioned.
							</p>
							<div class="prospects__not-proceeding-actions">
								<Button
									type="button"
									variant="tertiary"
									disabled={markNotProceeding.isPending}
									onclick={() => (confirmingNotProceeding = false)}>Cancel</Button
								>
								<Button
									type="button"
									variation="destructive"
									loading={markNotProceeding.isPending}
									onclick={() => markNotProceeding.mutate()}>Confirm not proceeding</Button
								>
							</div>
						</div>
					{/if}

					{#if confirmingProvision}
						<div class="prospects__provision-confirm" role="alertdialog" aria-live="assertive">
							<span aria-hidden="true">{@html checkIcon}</span>
							<div>
								<p>
									This creates the <strong>{detail.business_name}</strong> organization and its
									first administrator account, <strong>{administratorEmail(detail)}</strong>, on the
									<strong>{packageName(detail.package_snapshot)}</strong> package. A single-use password-setup
									email is sent to the administrator immediately; they cannot sign in until they use it.
								</p>
								<div class="prospects__provision-actions">
									<Button
										type="button"
										variant="tertiary"
										disabled={provisionOrganization.isPending}
										onclick={() => (confirmingProvision = false)}>Cancel</Button
									>
									<Button
										type="button"
										loading={provisionOrganization.isPending}
										onclick={() => provisionOrganization.mutate()}>Confirm provisioning</Button
									>
								</div>
							</div>
						</div>
					{/if}

					<details class="prospects__history">
						<summary>View private history</summary>
						<div class="prospects__history-content">
							<dl>
								<div>
									<dt>Phone</dt>
									<dd>{detail.main_contact_phone}</dd>
								</div>
								<div>
									<dt>Location</dt>
									<dd>{detail.city_country} · {detail.time_zone}</dd>
								</div>
								<div>
									<dt>Initial administrator</dt>
									<dd>{detail.initial_administrator_name ?? 'Not supplied'}</dd>
								</div>
								<div>
									<dt>Administrator email</dt>
									<dd>{detail.initial_administrator_email ?? 'Not supplied'}</dd>
								</div>
								<div>
									<dt>Data purge after</dt>
									<dd>{formatDate(detail.personal_data_purge_after)}</dd>
								</div>
							</dl>
							{#if detail.note}<p class="prospects__note">
									<strong>Applicant note:</strong>
									{detail.note}
								</p>{/if}
							{#if prospectDetail.data.original_submission}
								<details>
									<summary>Original submission record</summary>
									<pre>{jsonPreview(prospectDetail.data.original_submission.submitted_data)}</pre>
								</details>
							{/if}
							{#if prospectDetail.data.corrections.length > 0}
								<div class="prospects__corrections">
									<h3>Correction history</h3>
									{#each prospectDetail.data.corrections as correction (correction.id)}
										<article>
											<strong>{correction.reason}</strong>
											<small
												>{correction.actor_owner_email} · {formatDate(correction.created_at)}</small
											>
										</article>
									{/each}
								</div>
							{/if}
						</div>
					</details>
				</div>
			{/if}
		</section>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.prospects {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.prospects h1,
	.prospects h2,
	.prospects h3,
	.prospects p {
		margin: 0;
	}

	.prospects h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.prospects h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}

	.prospects h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}

	.prospects__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.prospects__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.prospects__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.prospects__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.prospects__filters {
		display: flex;
		align-items: flex-end;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.prospects__filter-field {
		display: grid;
		width: min(260px, 100%);
		gap: var(--space-small);

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}
	}

	.prospects__filter-field--search {
		width: min(420px, 100%);
		flex: 1 1 320px;
	}

	.prospects__filters :global(.button) {
		margin-left: auto;
	}

	.prospects__list-meta,
	.prospects__table-footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.prospects__list-meta {
		padding: 0 var(--space-small);
	}

	.prospects__list-meta strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}

	.prospects__table-panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.prospects__table-wrap {
		overflow-x: auto;
	}

	.prospects table {
		width: 100%;
		min-width: 880px;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}

	.prospects th,
	.prospects td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}

	.prospects thead {
		background: var(--color-surface--background--subtle);
	}

	.prospects thead th {
		color: var(--color-text--secondary);
		font-weight: 700;
		white-space: nowrap;
	}

	.prospects tbody th {
		color: var(--color-heading);
		font-weight: 700;
	}

	.prospects tbody th strong,
	.prospects tbody th small,
	.prospects tbody td strong,
	.prospects tbody td small {
		display: block;
	}

	.prospects tbody small {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		line-height: var(--typography--lineHeight-tighter);
	}

	.prospects tbody tr {
		transition: background-color var(--timing-quick);

		&:hover,
		&.prospects__table-row--selected {
			background: var(--color-surface--hover);
		}

		&:last-child th,
		&:last-child td {
			border-bottom: 0;
		}
	}

	.prospects__warning-label {
		display: flex !important;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-warning--onSurface) !important;
	}

	.prospects__warning-label span,
	.prospects__warning-label span :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	.prospects__row-action {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		&:hover {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		& :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	.prospects__table-footer {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}

	.prospects__quiet-button {
		min-height: 32px;
		padding: 0;
		border: 0;
		color: var(--color-interactive);
		background: transparent;
		font: inherit;
		font-weight: 600;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.prospects__state,
	.prospects__review-state {
		padding: var(--space-large);
	}

	.prospects__review {
		display: flex;
		align-items: flex-start;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-informative);
		border-radius: var(--radius-base);
		background: var(--color-informative--surface);
	}

	.prospects__review-icon {
		display: grid;
		width: 40px;
		height: 40px;
		flex: 0 0 40px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-surface);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.prospects__review-content {
		min-width: 0;
		flex: 1;
		color: var(--color-informative--onSurface);

		> p:not(.prospects__eyebrow) {
			margin-top: var(--space-small);
			line-height: var(--typography--lineHeight-large);
		}
	}

	.prospects__review-heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.prospects__review-details,
	.prospects__history-content > dl {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
		margin: var(--space-base) 0 0;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		dd {
			margin: var(--space-smaller) 0 0;
			color: var(--color-heading);
			overflow-wrap: anywhere;
		}
	}

	.prospects__feedback {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
	}

	.prospects__feedback--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}

	.prospects__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}

	.prospects__owner-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		margin-top: var(--space-base);
	}

	.prospects__setup-status {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin-top: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);

		p {
			display: flex;
			align-items: flex-start;
			gap: var(--space-smaller);
			margin: 0;
			line-height: var(--typography--lineHeight-large);
		}

		span :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
			color: var(--color-icon--secondary);
		}
	}

	.prospects__setup-status-error {
		display: block;
		color: var(--color-critical--onSurface);
	}

	.prospects__correction-form {
		display: grid;
		gap: var(--space-base);
		margin-top: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-informative);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.prospects__form-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);

		label {
			display: grid;
			gap: var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		input,
		textarea {
			width: 100%;
			min-height: 40px;
			box-sizing: border-box;
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface);
			font: inherit;
		}

		textarea {
			min-height: 72px;
			resize: vertical;
		}

		input:focus-visible,
		textarea:focus-visible {
			outline: none;
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-focus);
		}
	}

	.prospects__form-wide {
		grid-column: 1 / -1;
	}

	.prospects__payment-price-note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		strong {
			color: var(--color-heading);
		}
	}

	.prospects__form-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	.prospects__not-proceeding-confirm {
		display: grid;
		gap: var(--space-small);
		margin-top: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-critical);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-small);

		span {
			color: var(--color-critical);
		}

		span :global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.prospects__not-proceeding-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	.prospects__provision-confirm {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		margin-top: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-success);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-small);

		> span {
			color: var(--color-success);
		}

		> span :global(svg) {
			width: 20px;
			height: 20px;
		}

		p {
			line-height: var(--typography--lineHeight-large);
		}
	}

	.prospects__provision-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-base);
	}

	.prospects__history {
		margin-top: var(--space-base);
		color: var(--color-informative--onSurface);

		summary {
			width: fit-content;
			color: var(--color-interactive);
			font-weight: 600;
			cursor: pointer;
		}
	}

	.prospects__history-content {
		display: grid;
		gap: var(--space-base);
		margin-top: var(--space-base);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-informative);
	}

	.prospects__note {
		line-height: var(--typography--lineHeight-large);
		white-space: pre-wrap;
	}

	.prospects pre {
		max-height: 240px;
		overflow: auto;
		margin: var(--space-base) 0 0;
		padding: var(--space-base);
		border-radius: var(--radius-small);
		color: var(--color-text);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}

	.prospects__corrections {
		display: grid;
		gap: var(--space-small);

		article {
			display: grid;
			gap: var(--space-smaller);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-informative);
			border-radius: var(--radius-small);
			background: var(--color-surface);
		}

		small {
			color: var(--color-text--secondary);
		}
	}

	.prospects__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 900px) {
		.prospects__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}

		.prospects__review-details,
		.prospects__history-content > dl {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 767px) {
		.prospects__filters,
		.prospects__list-meta,
		.prospects__table-footer,
		.prospects__review {
			align-items: stretch;
			flex-direction: column;
		}

		.prospects__filter-field,
		.prospects__filter-field--search {
			width: 100%;
		}

		.prospects__filters :global(.button) {
			margin-left: 0;
		}

		.prospects__table-footer {
			gap: var(--space-small);
		}
	}

	@media (max-width: 639px) {
		.prospects h1 {
			font-size: 28px;
		}

		.prospects__summary,
		.prospects__review-details,
		.prospects__history-content > dl,
		.prospects__form-grid {
			grid-template-columns: 1fr;
		}

		.prospects__review {
			padding: var(--space-base);
		}

		.prospects__review-heading {
			align-items: flex-start;
			flex-direction: column;
		}
	}
</style>
