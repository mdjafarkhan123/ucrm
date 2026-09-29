<script lang="ts">
	import type {
		EffectiveAccess,
		CommercialState,
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
	import FreeAccessActions from '$lib/components/jafar/FreeAccessActions.svelte';
	import SmsCreditTopupActions from '$lib/components/jafar/SmsCreditTopupActions.svelte';
	import SmsHoldActions from '$lib/components/jafar/SmsHoldActions.svelte';
	import SmsPromotionalCreditActions from '$lib/components/jafar/SmsPromotionalCreditActions.svelte';
	import SmsAdjustmentRefundActions from '$lib/components/jafar/SmsAdjustmentRefundActions.svelte';
	import { jafarOrganizationKey, jafarOrganizationsKey } from '$lib/jafar/query-keys';
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
		commercialQuery,
		organizationId,
		actionError = $bindable(''),
		actionMessage = $bindable('')
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
		commercialQuery: CreateQueryResult<CommercialState, Error>;
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
		void queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) });
		void queryClient.invalidateQueries({ queryKey: jafarOrganizationsKey });
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

	// Limit override (marketing_email_recipients) --------------------------
	let editingMarketingLimit = $state(false);
	let marketingLimitOverrideState = $state<'inherit' | 'unlimited' | 'not_included' | 'numeric'>(
		'numeric'
	);
	let marketingLimitOverrideValue = $state('');
	let marketingLimitOverrideStartsAt = $state('');
	let marketingLimitOverrideExpiry = $state('');
	let marketingLimitOverrideReason = $state('');

	function handleMarketingLimitOverrideStartsAtChange(value: DateTimePickerValue) {
		marketingLimitOverrideStartsAt = dateTimePickerValueToLocalString(value);
	}

	function handleMarketingLimitOverrideExpiryChange(value: CalendarDate | undefined) {
		marketingLimitOverrideExpiry = calendarDateToString(value);
	}

	const marketingLimitOverrideMutation = createMutation<
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
				`/api/jafar/organizations/${organizationId}/limit-overrides/marketing_email_recipients`,
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
			editingMarketingLimit = false;
			actionMessage = 'Marketing email allowance exception updated.';
			invalidateOrganization();
		}
	}));

	function startEditingMarketingLimit() {
		editingMarketingLimit = true;
		marketingLimitOverrideState = access?.limits.marketing_email_recipients.state ?? 'numeric';
		marketingLimitOverrideValue = access?.limits.marketing_email_recipients.value?.toString() ?? '';
		marketingLimitOverrideStartsAt = localDateTimeValue(new Date());
		marketingLimitOverrideExpiry = '';
		marketingLimitOverrideReason = '';
	}
	function submitMarketingLimitOverride(event: SubmitEvent) {
		event.preventDefault();
		if (!marketingLimitOverrideReason.trim() || !marketingLimitOverrideStartsAt) return;
		marketingLimitOverrideMutation.mutate({
			override_state: marketingLimitOverrideState,
			limit_value:
				marketingLimitOverrideState === 'numeric' ? Number(marketingLimitOverrideValue) : null,
			starts_at: localDateTimeToIso(marketingLimitOverrideStartsAt),
			expires_at: marketingLimitOverrideExpiry
				? new Date(marketingLimitOverrideExpiry).toISOString()
				: null,
			reason: marketingLimitOverrideReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
	function clearMarketingLimitOverride() {
		editingMarketingLimit = true;
		marketingLimitOverrideState = 'inherit';
		marketingLimitOverrideStartsAt = localDateTimeValue(new Date());
		marketingLimitOverrideExpiry = '';
		marketingLimitOverrideReason = '';
	}

	const queryClient = useQueryClient();

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
		'reporting.advanced': 'Advanced reporting',
		'growth.reputation': 'Reviews and reputation',
		marketing: 'Marketing'
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
					<p>Review the package, paid-through and grace state, and exceptions.</p>
				</div>

				<div class="organization-detail__commercial-grid">
					<Card class="organization-detail__commercial-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html receiptIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Package</p>
							<h3>{access.package?.name ?? 'No package'}</h3>
							<p>
								{access.package
									? `Edition ${access.package.edition_number} · ${formatPrice(
											access.package.agreed_price_usd_cents,
											access.package.currency,
											access.package.billing_interval
										)}`
									: 'Every capability is off until a package is agreed.'}
							</p>
						</div>
						<p class="organization-detail__form-note">
							Changing a customer's package returns with the new package tools.
						</p>
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
					<SmsCreditTopupActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<SmsHoldActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<SmsPromotionalCreditActions organizationId={access.organization.id} />
				</Card>
				<Card class="organization-detail__commercial-explainer">
					<SmsAdjustmentRefundActions organizationId={access.organization.id} />
				</Card>

				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Free access</h3>
						<FreeAccessActions
							organizationId={access.organization.id}
							hasPackageAssignment={access.package !== null}
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

				<Card class="organization-detail__commercial-explainer">
					<div>
						<h3>Marketing email allowance</h3>
						<p>
							{access.limits.marketing_email_recipients.state === 'unlimited'
								? 'Unlimited recipients'
								: access.limits.marketing_email_recipients.state === 'numeric'
									? `${access.limits.marketing_email_recipients.value} recipients per month`
									: 'Not included'}
							<Badge
								status={access.limits.marketing_email_recipients.source === 'override'
									? 'informative'
									: 'inactive'}
								>{access.limits.marketing_email_recipients.source === 'override'
									? 'Exception'
									: 'Package default'}</Badge
							>
						</p>
						{#if editingMarketingLimit}
							<form
								onsubmit={submitMarketingLimitOverride}
								class="organization-detail__inline-form"
							>
								<Select
									id="marketing-limit-override-state"
									ariaLabel="Marketing email allowance exception state"
									options={LIMIT_OVERRIDE_STATE_OPTIONS}
									bind:value={marketingLimitOverrideState}
								/>
								{#if marketingLimitOverrideState === 'numeric'}
									<Input
										id="marketing-limit-override-value"
										label="Recipients per month"
										type="number"
										min="0"
										bind:value={marketingLimitOverrideValue}
									/>
								{/if}
								<CalendarPicker
									id="marketing-limit-override-expiry"
									label="Expires (leave blank for permanent)"
									value={calendarDateFromString(marketingLimitOverrideExpiry)}
									onchange={handleMarketingLimitOverrideExpiryChange}
								/>
								<DateTimePicker
									id="marketing-limit-override-starts-at"
									dateLabel="Starts at date"
									timeLabel="Starts at time"
									value={dateTimePickerValueFromLocalString(marketingLimitOverrideStartsAt)}
									required
									onchange={handleMarketingLimitOverrideStartsAtChange}
								/>
								<Input
									id="marketing-limit-override-reason"
									label="Private reason"
									bind:value={marketingLimitOverrideReason}
								/>
								<div class="organization-detail__inline-form-actions">
									<Button type="submit" loading={marketingLimitOverrideMutation.isPending}
										>Save exception</Button
									>
									<Button
										type="button"
										variant="secondary"
										variation="subtle"
										onclick={() => (editingMarketingLimit = false)}>Cancel</Button
									>
								</div>
							</form>
						{:else}
							<div class="organization-detail__inline-form-actions">
								<Button variant="secondary" variation="subtle" onclick={startEditingMarketingLimit}
									>Change Marketing exception</Button
								>
								{#if access.limits.marketing_email_recipients.source === 'override'}
									<Button
										variant="secondary"
										variation="subtle"
										loading={marketingLimitOverrideMutation.isPending}
										onclick={clearMarketingLimitOverride}>Clear exception</Button
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
