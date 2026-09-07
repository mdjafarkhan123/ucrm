<script lang="ts">
	import type {
		EffectiveAccess,
		CommercialState,
		PackagesCatalogResponse,
		MutationResponse
	} from '$lib/components/jafar/organization/types';
	import type { CreateQueryResult } from '@tanstack/svelte-query';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import type { CalendarDate } from '@internationalized/date';
	import type { DateTimePickerValue } from '$lib/components/ui/date-time';
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import CommercialActions from '$lib/components/jafar/CommercialActions.svelte';
	import FreeAccessActions from '$lib/components/jafar/FreeAccessActions.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso
	} from '$lib/components/ui/date-time';
	import { formatCalendarDate, formatDateTime, formatPrice } from './format';
	let {
		access,
		preview,
		packagesCatalogQuery,
		commercialQuery,
		publishedVersionOptions,
		organizationId,
		actionError = $bindable(''),
		actionMessage = $bindable('')
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
		packagesCatalogQuery: CreateQueryResult<PackagesCatalogResponse, Error>;
		commercialQuery: CreateQueryResult<CommercialState, Error>;
		publishedVersionOptions: { value: string; label: string }[];
		organizationId: string | undefined;
		actionError: string;
		actionMessage: string;
	} = $props();

	const OVERRIDE_STATE_OPTIONS = [
		{ value: 'inherit', label: 'Inherit from package' },
		{ value: 'on', label: 'Force on' },
		{ value: 'off', label: 'Force off' }
	];
	const LIMIT_OVERRIDE_STATE_OPTIONS = [
		{ value: 'inherit', label: 'Inherit from package' },
		{ value: 'numeric', label: 'Set a numeric limit' },
		{ value: 'not_included', label: 'Not included' },
		{ value: 'unlimited', label: 'Unlimited' }
	];

	function localDateTimeValue(value: Date) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(value));
	}

	function clearFeedback() {
		actionError = '';
		actionMessage = '';
	}

	function invalidateOrganization() {
		void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations', organizationId] });
		void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
	}

	// Package change ----------------------------------------------------------
	let editingPackage = $state(false);
	let packageChangeTarget = $state('');
	let packageChangeReason = $state('');

	const packageChangeMutation = createMutation<
		MutationResponse,
		Error,
		{ package_version_id: string; reason: string; idempotency_key: string }
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/package`, {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The package could not be changed.');
			return result;
		},
		onMutate: clearFeedback,
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			editingPackage = false;
			packageChangeTarget = '';
			packageChangeReason = '';
			actionMessage = 'Package updated.';
			invalidateOrganization();
		}
	}));

	function submitPackageChange(event: SubmitEvent) {
		event.preventDefault();
		if (!packageChangeTarget || !packageChangeReason.trim()) return;
		packageChangeMutation.mutate({
			package_version_id: packageChangeTarget,
			reason: packageChangeReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}

	// Legacy package-version assignment (moves a legacy org onto a real version) --
	let showLegacyAssignForm = $state(false);
	let legacyVersionId = $state('');
	let legacyPaidThrough = $state('');
	let legacyReason = $state('');

	const legacyAssignMutation = createMutation<
		MutationResponse,
		Error,
		{ package_version_id: string; paid_through_date: string; reason: string }
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/package-version`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The package version could not be assigned.');
			return result;
		},
		onMutate: clearFeedback,
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			showLegacyAssignForm = false;
			legacyVersionId = '';
			legacyPaidThrough = '';
			legacyReason = '';
			actionMessage = 'Package version assigned and paid-through date recorded.';
			invalidateOrganization();
		}
	}));

	function submitLegacyAssign(event: SubmitEvent) {
		event.preventDefault();
		if (!legacyVersionId || !legacyPaidThrough || !legacyReason.trim()) return;
		legacyAssignMutation.mutate({
			package_version_id: legacyVersionId,
			paid_through_date: legacyPaidThrough,
			reason: legacyReason.trim()
		});
	}

	// Feature overrides ------------------------------------------------------
	let editingFeatureKey = $state<string | null>(null);
	let featureOverrideState = $state<'inherit' | 'on' | 'off'>('inherit');
	let featureOverrideStartsAt = $state('');
	let featureOverrideExpiry = $state('');
	let featureOverrideReason = $state('');

	function handleFeatureOverrideStartsAtChange(value: DateTimePickerValue) {
		featureOverrideStartsAt = dateTimePickerValueToLocalString(value);
	}

	function handleFeatureOverrideExpiryChange(value: CalendarDate | undefined) {
		featureOverrideExpiry = calendarDateToString(value);
	}

	const featureOverrideMutation = createMutation<
		MutationResponse,
		Error,
		{
			featureKey: string;
			override_state: 'inherit' | 'on' | 'off';
			starts_at: string;
			expires_at: string | null;
			reason: string;
			idempotency_key: string;
		}
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/feature-overrides/${input.featureKey}`,
				{
					method: 'PUT',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						override_state: input.override_state,
						starts_at: input.starts_at,
						expires_at: input.expires_at,
						reason: input.reason,
						idempotency_key: input.idempotency_key
					})
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The feature override could not be changed.');
			return result;
		},
		onMutate: clearFeedback,
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			editingFeatureKey = null;
			featureOverrideReason = '';
			actionMessage = 'Feature exception updated.';
			invalidateOrganization();
		}
	}));

	function startEditingFeature(featureKey: string) {
		editingFeatureKey = featureKey;
		const existing = access?.feature_overrides[featureKey];
		featureOverrideState = existing ? existing.state : 'inherit';
		featureOverrideStartsAt = existing?.starts_at
			? existing.starts_at.slice(0, 16)
			: localDateTimeValue(new Date());
		featureOverrideExpiry = existing?.expires_at ? existing.expires_at.slice(0, 10) : '';
		featureOverrideReason = '';
	}
	function submitFeatureOverride(event: SubmitEvent) {
		event.preventDefault();
		if (!editingFeatureKey) return;
		if (!featureOverrideReason.trim() || !featureOverrideStartsAt) return;
		featureOverrideMutation.mutate({
			featureKey: editingFeatureKey,
			override_state: featureOverrideState,
			starts_at: localDateTimeToIso(featureOverrideStartsAt),
			expires_at: featureOverrideExpiry ? new Date(featureOverrideExpiry).toISOString() : null,
			reason: featureOverrideReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}

	// Limit override (employee_seats) ---------------------------------------
	let editingLimit = $state(false);
	let limitOverrideState = $state<'inherit' | 'unlimited' | 'not_included' | 'numeric'>('numeric');
	let limitOverrideValue = $state('');
	let limitOverrideStartsAt = $state('');
	let limitOverrideExpiry = $state('');
	let limitOverrideReason = $state('');

	function handleLimitOverrideStartsAtChange(value: DateTimePickerValue) {
		limitOverrideStartsAt = dateTimePickerValueToLocalString(value);
	}

	function handleLimitOverrideExpiryChange(value: CalendarDate | undefined) {
		limitOverrideExpiry = calendarDateToString(value);
	}

	const limitOverrideMutation = createMutation<
		MutationResponse,
		Error,
		{
			override_state: 'inherit' | 'unlimited' | 'not_included' | 'numeric';
			limit_value?: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string;
			idempotency_key: string;
		}
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/limit-overrides/employee_seats`,
				{
					method: 'PUT',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(input)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The limit override could not be changed.');
			return result;
		},
		onMutate: clearFeedback,
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			editingLimit = false;
			actionMessage = 'Seat limit exception updated.';
			invalidateOrganization();
		}
	}));

	function startEditingLimit() {
		editingLimit = true;
		limitOverrideState = access?.limits.employee_seats.state ?? 'numeric';
		limitOverrideValue = access?.limits.employee_seats.value?.toString() ?? '';
		limitOverrideStartsAt = localDateTimeValue(new Date());
		limitOverrideExpiry = '';
		limitOverrideReason = '';
	}
	function submitLimitOverride(event: SubmitEvent) {
		event.preventDefault();
		if (!limitOverrideReason.trim() || !limitOverrideStartsAt) return;
		limitOverrideMutation.mutate({
			override_state: limitOverrideState,
			limit_value: limitOverrideState === 'numeric' ? Number(limitOverrideValue) : null,
			starts_at: localDateTimeToIso(limitOverrideStartsAt),
			expires_at: limitOverrideExpiry ? new Date(limitOverrideExpiry).toISOString() : null,
			reason: limitOverrideReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
	function clearLimitOverride() {
		editingLimit = true;
		limitOverrideState = 'inherit';
		limitOverrideStartsAt = localDateTimeValue(new Date());
		limitOverrideExpiry = '';
		limitOverrideReason = '';
	}

	// Limit override (website_chat_widgets) ----------------------------------
	let editingWidgetsLimit = $state(false);
	let widgetsLimitOverrideState = $state<'inherit' | 'unlimited' | 'not_included' | 'numeric'>(
		'numeric'
	);
	let widgetsLimitOverrideValue = $state('');
	let widgetsLimitOverrideStartsAt = $state('');
	let widgetsLimitOverrideExpiry = $state('');
	let widgetsLimitOverrideReason = $state('');

	function handleWidgetsLimitOverrideStartsAtChange(value: DateTimePickerValue) {
		widgetsLimitOverrideStartsAt = dateTimePickerValueToLocalString(value);
	}

	function handleWidgetsLimitOverrideExpiryChange(value: CalendarDate | undefined) {
		widgetsLimitOverrideExpiry = calendarDateToString(value);
	}

	const widgetsLimitOverrideMutation = createMutation<
		MutationResponse,
		Error,
		{
			override_state: 'inherit' | 'unlimited' | 'not_included' | 'numeric';
			limit_value?: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string;
			idempotency_key: string;
		}
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/limit-overrides/website_chat_widgets`,
				{
					method: 'PUT',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(input)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The limit override could not be changed.');
			return result;
		},
		onMutate: clearFeedback,
		onError: (error) => (actionError = error.message),
		onSuccess: () => {
			editingWidgetsLimit = false;
			actionMessage = 'Website Chat widget limit exception updated.';
			invalidateOrganization();
		}
	}));

	function startEditingWidgetsLimit() {
		editingWidgetsLimit = true;
		widgetsLimitOverrideState = access?.limits.website_chat_widgets.state ?? 'numeric';
		widgetsLimitOverrideValue = access?.limits.website_chat_widgets.value?.toString() ?? '';
		widgetsLimitOverrideStartsAt = localDateTimeValue(new Date());
		widgetsLimitOverrideExpiry = '';
		widgetsLimitOverrideReason = '';
	}
	function submitWidgetsLimitOverride(event: SubmitEvent) {
		event.preventDefault();
		if (!widgetsLimitOverrideReason.trim() || !widgetsLimitOverrideStartsAt) return;
		widgetsLimitOverrideMutation.mutate({
			override_state: widgetsLimitOverrideState,
			limit_value:
				widgetsLimitOverrideState === 'numeric' ? Number(widgetsLimitOverrideValue) : null,
			starts_at: localDateTimeToIso(widgetsLimitOverrideStartsAt),
			expires_at: widgetsLimitOverrideExpiry
				? new Date(widgetsLimitOverrideExpiry).toISOString()
				: null,
			reason: widgetsLimitOverrideReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
	function clearWidgetsLimitOverride() {
		editingWidgetsLimit = true;
		widgetsLimitOverrideState = 'inherit';
		widgetsLimitOverrideStartsAt = localDateTimeValue(new Date());
		widgetsLimitOverrideExpiry = '';
		widgetsLimitOverrideReason = '';
	}

	const queryClient = useQueryClient();
	const isLegacyUnversioned = $derived(access ? access.package.version_id === null : false);

	const FEATURE_LABELS: Record<string, string> = {
		'core.dashboard': 'Dashboard and workspace overview',
		'core.customers_properties': 'Customers and properties',
		'core.requests_assessments': 'Requests and assessments',
		'core.quotes': 'Quotes and proposals',
		'core.jobs': 'Jobs and work records',
		'core.schedule': 'Visits and schedule',
		'core.invoices_payments': 'Invoices and payments',
		'core.team': 'Team and employee management',
		'sales.pipeline': 'Sales pipeline and opportunities',
		'communications.inbox': 'Unified inbox',
		'portal.client': 'Customer-facing portal',
		'automation.workflows': 'Workflow automations',
		'reporting.advanced': 'Advanced reporting'
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="access">
	<div class="organization-workspace">
		{#if preview}
			<section class="organization-detail__section" aria-labelledby="commercial-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Commercial access</p>
					<h2 id="commercial-title">Package and access position</h2>
					<p>
						Review the commercial record before considering an access change. This preview does not
						infer or change live eligibility.
					</p>
				</div>
				<div class="organization-detail__commercial-grid">
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html receiptIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Activated package</p>
							<h3>{preview?.commercial.packageName}</h3>
							<p>{preview?.commercial.packageVersion}</p>
						</div>
						<dl>
							<div>
								<dt>Paid through</dt>
								<dd>{preview?.commercial.paidThrough}</dd>
							</div>
							<div>
								<dt>Grace</dt>
								<dd>{preview?.commercial.grace}</dd>
							</div>
						</dl>
					</Card>
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon">{@html shieldIcon}</div>
						<div>
							<p class="organization-detail__card-label">Access arrangement</p>
							<h3>{preview?.commercial.freeAccess}</h3>
							<p>{preview?.commercial.exception}</p>
						</div>
						<span class="organization-detail__safe-label">Record changes are unavailable</span>
					</Card>
				</div>
				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Capabilities and limits</h3>
						<p>
							Package rules, feature exceptions, and usage limits will appear here only after their
							secure enforcement and measurement are connected. This preview deliberately does not
							invent access values.
						</p>
					</div>
					<Badge status="inactive">Not connected</Badge>
				</Card>
			</section>
		{:else if access}
			<section class="organization-detail__section" aria-labelledby="commercial-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Commercial access</p>
					<h2 id="commercial-title">Package and access position</h2>
					<p>Change the package, review paid-through and grace state, and manage exceptions.</p>
				</div>

				<div class="organization-detail__commercial-grid">
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html receiptIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Package</p>
							<h3>{access.package.display_name}</h3>
							<p>
								{formatPrice(
									access.package.price_usd_cents,
									access.package.currency,
									access.package.billing_period
								)}
							</p>
						</div>
						{#if editingPackage}
							<form onsubmit={submitPackageChange} class="organization-detail__inline-form">
								<Select
									id="package-change-target"
									ariaLabel="Target published package version"
									placeholder={packagesCatalogQuery.isPending
										? 'Loading published versions…'
										: 'Choose a published version'}
									options={publishedVersionOptions.filter(
										(option) => option.value !== access?.package.version_id
									)}
									bind:value={packageChangeTarget}
								/>
								<Input
									id="package-change-reason"
									label="Private reason"
									bind:value={packageChangeReason}
								/>
								<p class="organization-detail__form-note">
									The selected published version takes effect immediately. The prior version, new
									version, reason, and time are retained in owner history.
								</p>
								<div class="organization-detail__inline-form-actions">
									<Button type="submit" loading={packageChangeMutation.isPending}
										>Save package change</Button
									>
									<Button
										type="button"
										variant="secondary"
										variation="subtle"
										onclick={() => (editingPackage = false)}>Cancel</Button
									>
								</div>
							</form>
						{:else}
							<Button variant="secondary" variation="subtle" onclick={() => (editingPackage = true)}
								>Change package</Button
							>
						{/if}
					</Card>

					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon">{@html calendarIcon}</div>
						<div>
							<p class="organization-detail__card-label">Paid-through and grace</p>
							<h3>{formatCalendarDate(access.billing.paid_through_date)}</h3>
							<p>
								{access.billing.is_in_grace
									? `In grace until ${formatDateTime(access.billing.grace_ends_at)}`
									: access.billing.is_overdue
										? 'Past the 7-day grace period'
										: 'Not in grace'}
							</p>
						</div>
						<Badge
							status={!access.billing.paid_through_date
								? 'warning'
								: access.billing.is_overdue && !access.billing.is_in_grace
									? 'critical'
									: access.billing.is_in_grace
										? 'warning'
										: 'success'}
							>{!access.billing.paid_through_date
								? 'Needs setup'
								: access.billing.is_overdue && !access.billing.is_in_grace
									? 'Past grace'
									: access.billing.is_in_grace
										? 'In grace'
										: 'Current'}</Badge
						>
						<dl>
							<div>
								<dt>Source</dt>
								<dd>{access.billing.paid_through_source ?? 'Not recorded'}</dd>
							</div>
							<div>
								<dt>Commercial timezone</dt>
								<dd>{commercialQuery.data?.settings?.commercial_timezone ?? 'Not recorded'}</dd>
							</div>
						</dl>
					</Card>
				</div>

				<Card class="organization-detail__commercial-explainer">
					{#if commercialQuery.isPending}
						<LoadingSkeleton variant="text" label="Loading commercial actions" />
					{:else if commercialQuery.isError}
						<ErrorState
							title="Commercial actions could not be loaded"
							description={commercialQuery.error instanceof Error
								? commercialQuery.error.message
								: 'Commercial actions could not be loaded. Try again.'}
							retry={() => commercialQuery.refetch()}
						/>
					{:else if commercialQuery.data}
						<CommercialActions
							organizationId={access.organization.id}
							lifecycleStatus={access.organization.lifecycle_status}
							currentPaidThroughDate={commercialQuery.data.state?.paid_through_date ?? null}
							originalEvents={commercialQuery.data.original_events}
						/>
					{/if}
				</Card>

				{#if isLegacyUnversioned}
					<Card class="organization-detail__commercial-explainer">
						<div>
							<h3>Assign a published package version</h3>
							<p>
								This organization still uses the legacy package column. Assigning a published
								version records an immutable billing baseline and unlocks free-access management.
							</p>
							{#if showLegacyAssignForm}
								<form onsubmit={submitLegacyAssign} class="organization-detail__inline-form">
									<Select
										id="legacy-assign-version"
										ariaLabel="Published version"
										placeholder={packagesCatalogQuery.isPending
											? 'Loading published versions…'
											: 'Choose a published version'}
										options={publishedVersionOptions}
										bind:value={legacyVersionId}
									/>
									<CalendarPicker
										id="legacy-assign-paid-through"
										label="Paid-through date"
										value={calendarDateFromString(legacyPaidThrough)}
										onchange={(value) => (legacyPaidThrough = calendarDateToString(value))}
									/>
									<Input
										id="legacy-assign-reason"
										label="Private reason"
										bind:value={legacyReason}
									/>
									<div class="organization-detail__inline-form-actions">
										<Button type="submit" loading={legacyAssignMutation.isPending}
											>Assign version</Button
										>
										<Button
											type="button"
											variant="secondary"
											variation="subtle"
											onclick={() => (showLegacyAssignForm = false)}>Cancel</Button
										>
									</div>
								</form>
							{/if}
						</div>
						{#if !showLegacyAssignForm}
							<Button onclick={() => (showLegacyAssignForm = true)}>Assign version</Button>
						{/if}
					</Card>
				{/if}

				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Free access</h3>
						<FreeAccessActions
							organizationId={access.organization.id}
							hasPackageAssignment={!isLegacyUnversioned}
							freeAccess={access.free_access}
						/>
					</div>
				</Card>

				<Card class="organization-detail__commercial-explainer organization-detail__capabilities">
					<div class="organization-detail__table-wrap">
						<table>
							<caption>Capabilities and exceptions</caption>
							<thead>
								<tr>
									<th scope="col">Capability</th>
									<th scope="col">Package default</th>
									<th scope="col">Effective</th>
									<th scope="col">Exception</th>
									<th scope="col">Private reason</th>
									<th scope="col"></th>
								</tr>
							</thead>
							<tbody>
								{#each Object.entries(FEATURE_LABELS) as [featureKey, label] (featureKey)}
									{@const override = access.feature_overrides[featureKey]}
									<tr>
										<td>{label}</td>
										<td>{access.package_features[featureKey] ? 'Included' : 'Not included'}</td>
										<td
											><Badge status={access.features[featureKey] ? 'success' : 'inactive'}
												>{access.features[featureKey] ? 'On' : 'Off'}</Badge
											></td
										>
										<td
											>{override
												? `${override.state === 'on' ? 'Forced on' : 'Forced off'}${override.expires_at ? ` until ${formatCalendarDate(override.expires_at.slice(0, 10))}` : ' (permanent)'}`
												: 'None'}</td
										>
										<td
											>{override?.is_legacy_import
												? 'Legacy import'
												: (override?.reason ?? '—')}</td
										>
										<td>
											<Button
												size="small"
												variant="secondary"
												variation="subtle"
												onclick={() => startEditingFeature(featureKey)}>Change</Button
											>
										</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
					{#if editingFeatureKey}
						<form onsubmit={submitFeatureOverride} class="organization-detail__inline-form">
							<p><strong>{FEATURE_LABELS[editingFeatureKey]}</strong></p>
							<Select
								id="feature-override-state"
								ariaLabel="Exception"
								options={OVERRIDE_STATE_OPTIONS}
								bind:value={featureOverrideState}
							/>
							{#if featureOverrideState !== 'inherit'}
								<CalendarPicker
									id="feature-override-expiry"
									label="Expires (leave blank for permanent)"
									value={calendarDateFromString(featureOverrideExpiry)}
									onchange={handleFeatureOverrideExpiryChange}
								/>
							{/if}
							<DateTimePicker
								id="feature-override-starts-at"
								dateLabel="Starts at date"
								timeLabel="Starts at time"
								value={dateTimePickerValueFromLocalString(featureOverrideStartsAt)}
								required
								onchange={handleFeatureOverrideStartsAtChange}
							/>
							<Input
								id="feature-override-reason"
								label="Private reason"
								bind:value={featureOverrideReason}
							/>
							<div class="organization-detail__inline-form-actions">
								<Button type="submit" loading={featureOverrideMutation.isPending}
									>Save exception</Button
								>
								<Button
									type="button"
									variant="secondary"
									variation="subtle"
									onclick={() => (editingFeatureKey = null)}>Cancel</Button
								>
							</div>
						</form>
					{/if}
				</Card>

				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Employee seat limit</h3>
						<p>
							{access.limits.employee_seats.state === 'unlimited'
								? 'Unlimited seats'
								: access.limits.employee_seats.state === 'numeric'
									? `${access.limits.employee_seats.value} seats`
									: 'Not included'}
							<Badge
								status={access.limits.employee_seats.source === 'override'
									? 'informative'
									: 'inactive'}
								>{access.limits.employee_seats.source === 'override'
									? 'Exception'
									: 'Package default'}</Badge
							>
						</p>
						{#if editingLimit}
							<form onsubmit={submitLimitOverride} class="organization-detail__inline-form">
								<Select
									id="limit-override-state"
									ariaLabel="Seat limit exception state"
									options={LIMIT_OVERRIDE_STATE_OPTIONS}
									bind:value={limitOverrideState}
								/>
								{#if limitOverrideState === 'numeric'}
									<Input
										id="limit-override-value"
										label="Seat count"
										type="number"
										min="0"
										bind:value={limitOverrideValue}
									/>
								{/if}
								<CalendarPicker
									id="limit-override-expiry"
									label="Expires (leave blank for permanent)"
									value={calendarDateFromString(limitOverrideExpiry)}
									onchange={handleLimitOverrideExpiryChange}
								/>
								<DateTimePicker
									id="limit-override-starts-at"
									dateLabel="Starts at date"
									timeLabel="Starts at time"
									value={dateTimePickerValueFromLocalString(limitOverrideStartsAt)}
									required
									onchange={handleLimitOverrideStartsAtChange}
								/>
								<Input
									id="limit-override-reason"
									label="Private reason"
									bind:value={limitOverrideReason}
								/>
								<div class="organization-detail__inline-form-actions">
									<Button type="submit" loading={limitOverrideMutation.isPending}
										>Save exception</Button
									>
									<Button
										type="button"
										variant="secondary"
										variation="subtle"
										onclick={() => (editingLimit = false)}>Cancel</Button
									>
								</div>
							</form>
						{:else}
							<div class="organization-detail__inline-form-actions">
								<Button variant="secondary" variation="subtle" onclick={startEditingLimit}
									>Change seat exception</Button
								>
								{#if access.limits.employee_seats.source === 'override'}
									<Button
										variant="secondary"
										variation="subtle"
										loading={limitOverrideMutation.isPending}
										onclick={clearLimitOverride}>Clear exception</Button
									>
								{/if}
							</div>
						{/if}
					</div>
				</Card>

				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Website Chat widgets limit</h3>
						<p>
							{access.limits.website_chat_widgets.state === 'unlimited'
								? 'Unlimited widgets'
								: access.limits.website_chat_widgets.state === 'numeric'
									? `${access.limits.website_chat_widgets.value} widgets`
									: 'Not included'}
							<Badge
								status={access.limits.website_chat_widgets.source === 'override'
									? 'informative'
									: 'inactive'}
								>{access.limits.website_chat_widgets.source === 'override'
									? 'Exception'
									: 'Package default'}</Badge
							>
						</p>
						{#if editingWidgetsLimit}
							<form onsubmit={submitWidgetsLimitOverride} class="organization-detail__inline-form">
								<Select
									id="widgets-limit-override-state"
									ariaLabel="Website Chat widgets limit exception state"
									options={LIMIT_OVERRIDE_STATE_OPTIONS}
									bind:value={widgetsLimitOverrideState}
								/>
								{#if widgetsLimitOverrideState === 'numeric'}
									<Input
										id="widgets-limit-override-value"
										label="Widget count"
										type="number"
										min="0"
										bind:value={widgetsLimitOverrideValue}
									/>
								{/if}
								<CalendarPicker
									id="widgets-limit-override-expiry"
									label="Expires (leave blank for permanent)"
									value={calendarDateFromString(widgetsLimitOverrideExpiry)}
									onchange={handleWidgetsLimitOverrideExpiryChange}
								/>
								<DateTimePicker
									id="widgets-limit-override-starts-at"
									dateLabel="Starts at date"
									timeLabel="Starts at time"
									value={dateTimePickerValueFromLocalString(widgetsLimitOverrideStartsAt)}
									required
									onchange={handleWidgetsLimitOverrideStartsAtChange}
								/>
								<Input
									id="widgets-limit-override-reason"
									label="Private reason"
									bind:value={widgetsLimitOverrideReason}
								/>
								<div class="organization-detail__inline-form-actions">
									<Button type="submit" loading={widgetsLimitOverrideMutation.isPending}
										>Save exception</Button
									>
									<Button
										type="button"
										variant="secondary"
										variation="subtle"
										onclick={() => (editingWidgetsLimit = false)}>Cancel</Button
									>
								</div>
							</form>
						{:else}
							<div class="organization-detail__inline-form-actions">
								<Button variant="secondary" variation="subtle" onclick={startEditingWidgetsLimit}
									>Change widgets exception</Button
								>
								{#if access.limits.website_chat_widgets.source === 'override'}
									<Button
										variant="secondary"
										variation="subtle"
										loading={widgetsLimitOverrideMutation.isPending}
										onclick={clearWidgetsLimitOverride}>Clear exception</Button
									>
								{/if}
							</div>
						{/if}
					</div>
				</Card>
			</section>
		{/if}
	</div>
</TabPanel>

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.organization-workspace {
		display: grid;
		gap: var(--space-larger);
		min-width: 0;
	}
	.organization-detail__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h2,
	h3,
	p {
		margin: 0;
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		line-height: var(--typography--lineHeight-tight);
	}
	.organization-detail__section-heading > p:last-child {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.organization-detail__section {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-base);
		min-width: 0;
	}
	.organization-detail__section > * {
		min-width: 0;
	}
	.organization-detail__card-icon {
		display: grid;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.organization-detail__card-icon {
		width: 36px;
		height: 36px;
	}
	.organization-detail__card-icon :global(svg) {
		width: 20px;
		height: 20px;
	}
	.organization-detail__card-label {
		margin-bottom: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	.organization-workspace dl {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-small);
		margin: 0;
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-workspace dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-workspace dd {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		overflow-wrap: anywhere;
	}
	.organization-detail__safe-label {
		width: fit-content;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__commercial-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-card) {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-card p:last-child) {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer) {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer > div) {
		flex: 1;
		min-width: 0;
		display: grid;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer h3) {
		font-size: var(--typography--fontSize-large);
	}
	.organization-workspace :global(.organization-detail__commercial-explainer p) {
		max-width: 78ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__table-wrap {
		overflow-x: auto;
	}
	.organization-workspace table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		text-align: left;
	}
	.organization-workspace caption {
		padding-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: left;
	}
	.organization-workspace th,
	.organization-workspace td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		vertical-align: top;
	}
	.organization-workspace th {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.organization-workspace td:first-child {
		color: var(--color-heading);
		font-weight: 700;
	}
	.organization-detail__inline-form {
		display: grid;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__inline-form-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.organization-workspace :global(.organization-detail__capabilities) {
		flex-direction: column;
	}
	@media (max-width: 639px) {
		.organization-detail__commercial-grid {
			grid-template-columns: 1fr;
		}
		.organization-workspace :global(.organization-detail__commercial-explainer) {
			flex-direction: column;
		}
	}
</style>
