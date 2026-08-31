<script lang="ts">
	import { dev } from '$app/environment';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import type { CalendarDate } from '@internationalized/date';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import plugIcon from '@tabler/icons/outline/plug-connected.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import { AlertDialog } from 'bits-ui';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ClosureActions from '$lib/components/jafar/ClosureActions.svelte';
	import CommercialActions from '$lib/components/jafar/CommercialActions.svelte';
	import EmailDomainActions from '$lib/components/jafar/EmailDomainActions.svelte';
	import EmailAllowanceActions from '$lib/components/jafar/EmailAllowanceActions.svelte';
	import EmailReputationActions from '$lib/components/jafar/EmailReputationActions.svelte';
	import EmailSendingPauseActions from '$lib/components/jafar/EmailSendingPauseActions.svelte';
	import WebsiteChatAllowanceActions from '$lib/components/jafar/WebsiteChatAllowanceActions.svelte';
	import WebsiteChatAuthorityActions from '$lib/components/jafar/WebsiteChatAuthorityActions.svelte';
	import AutomationAuthorityActions from '$lib/components/jafar/AutomationAuthorityActions.svelte';
	import FreeAccessActions from '$lib/components/jafar/FreeAccessActions.svelte';
	import LegacyReconcileActions from '$lib/components/jafar/LegacyReconcileActions.svelte';
	import LifecycleActions from '$lib/components/jafar/LifecycleActions.svelte';
	import TeamAccessActions from '$lib/components/jafar/TeamAccessActions.svelte';
	import {
		getOrganizationDetailPreview,
		organizationDetailScenarioLabel
	} from '$lib/jafar/organization-detail-preview';
	import type { DateTimePickerValue } from '$lib/components/ui/date-time';
	import {
		calendarDateFromString,
		calendarDateToString,
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso
	} from '$lib/components/ui/date-time';

	const queryClient = useQueryClient();

	type PackageKey = 'starter' | 'growth' | 'elite';

	type EffectiveAccess = {
		organization: { id: string; name: string; slug: string; lifecycle_status: string };
		billing: {
			paid_through_date: string | null;
			paid_through_source: string | null;
			grace_ends_at: string | null;
			is_overdue: boolean;
			is_in_grace: boolean;
		};
		package: {
			current_key: PackageKey;
			effective_key: PackageKey;
			version_id: string | null;
			version_number: number | null;
			status: 'draft' | 'published' | 'retired';
			display_name: string;
			public_description: string | null;
			price_usd_cents: number | null;
			currency: string;
			billing_period: string;
			scheduled_key: PackageKey | null;
			scheduled_effective_at: string | null;
		};
		features: Record<string, boolean>;
		package_features: Record<string, boolean>;
		feature_overrides: Record<
			string,
			{
				state: 'on' | 'off';
				starts_at: string;
				expires_at: string | null;
				reason: string | null;
				is_legacy_import: boolean;
			}
		>;
		limits: Record<
			'employee_seats' | 'website_chat_widgets',
			{
				state: 'unlimited' | 'not_included' | 'numeric';
				value: number | null;
				is_unlimited: boolean;
				source: 'package' | 'override';
			}
		>;
		free_access: {
			active: { grant_id: string; starts_at: string; access_until_date: string | null } | null;
			future: { grant_id: string; starts_at: string; access_until_date: string | null } | null;
		};
	};
	type AccessResponse = { access: EffectiveAccess; error?: string };
	type CommercialState = {
		organization: { id: string; name: string; lifecycle_status: string };
		state: {
			paid_through_date: string | null;
			paid_through_source: string | null;
			grace_ends_at: string | null;
		} | null;
		settings: { commercial_timezone: string; timezone_source: string } | null;
		original_events: {
			id: string;
			event_kind: string;
			occurred_at: string;
			summary: string;
			amount_usd_cents: number | null;
			paid_through_after: string | null;
			private_reference: string | null;
		}[];
		closure: { id: string; reason: string; started_at: string; deadline_at: string } | null;
		error?: string;
	};

	type PublishedVersion = {
		id: string;
		display_name: string;
		version_number: number;
		status: string;
		price_usd_cents: number;
		currency: string;
		billing_period: string;
	};
	type PackagesCatalogResponse = {
		packages: { package_key: PackageKey; display_name: string; versions: PublishedVersion[] }[];
		error?: string;
	};

	type TeamMember = {
		user_id: string;
		role: string;
		created_at: string;
		full_name: string | null;
		email: string | null;
		permission_overrides: { permission_key: string; override_state: string }[];
	};
	type TeamResponse = {
		organization: { id: string; name: string };
		members: TeamMember[];
		has_administrator: boolean;
		error?: string;
	};

	type HistoryEvent = {
		id: string;
		event_type: string;
		target_type: string;
		target_key: string | null;
		actor_email: string | null;
		occurred_at: string;
	};
	type HistoryResponse = {
		organization: { id: string; name: string };
		events: HistoryEvent[];
		applicationId: string | null;
		error?: string;
	};

	type OperationAttempt = {
		id: string;
		operation_type: string;
		target_kind: string;
		target_id: string;
		status: string;
		attempt_count: number;
		last_error: string | null;
		updated_at: string;
	};
	type OperationListResponse = {
		operations: OperationAttempt[];
		error?: string;
	};

	type MutationResponse = { error?: string };

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

	const HISTORY_EVENT_LABELS: Record<string, string> = {
		'organization.lifecycle_changed': 'Status changed',
		'package.updated': 'Package changed',
		'package.legacy_assigned': 'Legacy package assigned',
		'feature_override.updated': 'Feature override changed',
		'feature_override.inherited': 'Feature override cleared',
		'limit_override.updated': 'Seat limit override changed',
		'limit_override.inherited': 'Seat limit override cleared',
		'free_access.grant': 'Free access granted',
		'free_access.extend': 'Free access extended',
		'free_access.convert_to_forever': 'Free access converted to forever',
		'free_access.end': 'Free access ended',
		'commercial.initial_payment_confirmed': 'Initial payment confirmed',
		'commercial.renewal_confirmed': 'Renewal recorded',
		'commercial.payment_correction_recorded': 'Payment correction recorded',
		'commercial.refund_recorded': 'Refund recorded',
		'commercial.payment_reversal_recorded': 'Payment reversal recorded',
		'commercial.organization_suspended': 'Organization suspended',
		'commercial.organization_reactivated': 'Organization reactivated',
		'commercial.package_version_changed': 'Package version changed',
		'commercial.feature_exception_changed': 'Feature exception changed',
		'commercial.limit_exception_changed': 'Limit exception changed',
		'commercial.pending_setup_resolved': 'Legacy organization reviewed',
		'onboarding_application.provisioned': 'Organization provisioned from application',
		'onboarding_application.reviewed': 'Application marked reviewed',
		'onboarding_application.corrected': 'Application corrected',
		'onboarding_application.payment_confirmed': 'Application payment confirmed',
		'onboarding_application.payment_reversed': 'Application payment reversed',
		'onboarding_application.package_corrected': 'Application package corrected',
		'onboarding_application.duplicate_acknowledged': 'Marked not a duplicate',
		'onboarding_application.not_proceeding': 'Application marked not proceeding',
		'organization_member.profile_corrected': 'Team member profile corrected',
		'organization_member.administrator_email_recovered': 'Administrator email recovered'
	};

	const OPERATION_TYPE_LABELS: Record<string, string> = {
		setup_email_delivery: 'Setup email delivery',
		outbox_email_delivery: 'Queued email delivery',
		onboarding_application_provisioning: 'Organization provisioning'
	};
	const OPERATION_STATUS_LABELS: Record<string, string> = {
		pending: 'Pending',
		retrying: 'Retrying',
		acknowledged: 'Acknowledged'
	};

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

	function formatCalendarDate(value: string | null) {
		if (!value) return 'Not recorded';
		const [year, month, day] = value.split('-').map(Number);
		return new Date(year, month - 1, day).toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'long',
			day: 'numeric'
		});
	}
	function formatDateTime(value: string | null) {
		if (!value) return 'Not recorded';
		return new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
	}
	function formatPrice(cents: number | null, currency: string, period: string) {
		if (cents === null) return 'Not priced';
		return `$${(cents / 100).toFixed(2)} ${currency}/${period}`;
	}

	function localDateTimeValue(value: Date) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(value));
	}

	const scenario = $derived(page.url.searchParams.get('scenario'));
	const organizationId = $derived(page.params.organizationId);
	const preview = $derived(dev && scenario ? getOrganizationDetailPreview(scenario) : null);

	const accessQuery = createQuery<AccessResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'access'],
		enabled: !preview && Boolean(organizationId),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/access`);
			const result = (await response.json()) as AccessResponse;
			if (!response.ok) throw new Error(result.error ?? 'Organization access could not be loaded.');
			return result;
		}
	}));
	const access = $derived(accessQuery.data?.access ?? null);
	const isLoading = $derived(!preview && accessQuery.isPending);
	const errorDescription = $derived(
		accessQuery.error instanceof Error
			? accessQuery.error.message
			: 'Organization access could not be loaded. Try again.'
	);
	const isInitialError = $derived(!preview && accessQuery.isError && !access);
	const isStaleData = $derived(!preview && accessQuery.isError && Boolean(access));

	const commercialQuery = createQuery<CommercialState>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'commercial'],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/commercial`);
			const result = (await response.json()) as CommercialState;
			if (!response.ok) throw new Error(result.error ?? 'Commercial access could not be loaded.');
			return result;
		}
	}));

	const teamQuery = createQuery<TeamResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'team'],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/team`);
			const result = (await response.json()) as TeamResponse;
			if (!response.ok) throw new Error(result.error ?? 'Team members could not be loaded.');
			return result;
		}
	}));

	const historyQuery = createQuery<HistoryResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'history'],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/history`);
			const result = (await response.json()) as HistoryResponse;
			if (!response.ok) throw new Error(result.error ?? 'History could not be loaded.');
			return result;
		}
	}));

	const applicationId = $derived(historyQuery.data?.applicationId ?? null);

	const organizationOperationsQuery = createQuery<OperationListResponse>(() => ({
		queryKey: ['jafar', 'operations', 'target', organizationId],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/operations?target_id=${organizationId}`);
			const result = (await response.json()) as OperationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Operations could not be loaded.');
			return result;
		}
	}));

	const applicationOperationsQuery = createQuery<OperationListResponse>(() => ({
		queryKey: ['jafar', 'operations', 'target', applicationId],
		enabled: !preview && Boolean(applicationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/operations?target_id=${applicationId}`);
			const result = (await response.json()) as OperationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Operations could not be loaded.');
			return result;
		}
	}));

	const attentionOperations = $derived(
		[
			...(organizationOperationsQuery.data?.operations ?? []),
			...(applicationOperationsQuery.data?.operations ?? [])
		].sort((a, b) => (a.updated_at < b.updated_at ? 1 : a.updated_at > b.updated_at ? -1 : 0))
	);

	const isLegacyUnversioned = $derived(access ? access.package.version_id === null : false);

	const packagesCatalogQuery = createQuery<PackagesCatalogResponse>(() => ({
		queryKey: ['jafar', 'packages'],
		enabled: !preview && Boolean(access),
		queryFn: async () => {
			const response = await fetch('/api/jafar/packages');
			const result = (await response.json()) as PackagesCatalogResponse;
			if (!response.ok) throw new Error(result.error ?? 'Package definitions could not be loaded.');
			return result;
		}
	}));
	const publishedVersionOptions = $derived(
		(packagesCatalogQuery.data?.packages ?? []).flatMap((packageDefinition) =>
			packageDefinition.versions
				.filter((version) => version.status === 'published')
				.map((version) => ({
					value: version.id,
					label: `${packageDefinition.display_name} · v${version.version_number} — ${formatPrice(version.price_usd_cents, version.currency, version.billing_period)}`
				}))
		)
	);

	const pageTitle = $derived(
		isLoading
			? 'Loading organization · Organizations'
			: preview
				? `${preview.name} · Organizations`
				: access
					? `${access.organization.name} · Organizations`
					: 'Organization detail'
	);

	let confirmationOpen = $state(false);
	let actionError = $state('');
	let actionMessage = $state('');
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

	// Free access is managed by FreeAccessActions.svelte.
</script>

<svelte:head><title>{pageTitle}</title></svelte:head>

{#if isLoading}
	<!-- eslint-disable svelte/no-at-html-tags -->
	<main class="organization-detail" aria-busy="true">
		<nav class="organization-detail__breadcrumb" aria-label="Breadcrumb">
			<a href={resolve('/jafar/organizations')}
				><span aria-hidden="true">{@html arrowLeftIcon}</span> Organizations</a
			>
			<span aria-hidden="true">/</span>
			<span>Loading organization</span>
		</nav>

		<header class="organization-detail__header">
			<div class="organization-detail__loading-heading">
				<p class="organization-detail__eyebrow">Organization control room</p>
				<LoadingSkeleton variant="heading" label="Loading organization name" />
				<LoadingSkeleton variant="text" label="Loading organization summary" />
			</div>
			<a class="organization-detail__back-link" href={resolve('/jafar/organizations')}
				>Back to directory</a
			>
		</header>

		<section class="organization-detail__section" aria-labelledby="loading-overview-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Overview</p>
				<h2 id="loading-overview-title">Loading organization details</h2>
				<p>The page structure remains available while organization information is retrieved.</p>
			</div>
			<div class="organization-detail__overview-grid">
				<LoadingSkeleton variant="card" label="Loading organization overview" />
				<LoadingSkeleton variant="card" label="Loading lifecycle details" />
				<LoadingSkeleton variant="card" label="Loading next safe action" />
			</div>
		</section>

		<section class="organization-detail__at-a-glance" aria-label="Loading status summary">
			<LoadingSkeleton variant="card" label="Loading commercial access summary" />
			<LoadingSkeleton variant="card" label="Loading free access summary" />
			<LoadingSkeleton variant="card" label="Loading package status summary" />
		</section>

		<section
			class="organization-detail__loading-sections"
			aria-label="Loading organization sections"
		>
			<LoadingSkeleton variant="card" label="Loading commercial access" />
			<LoadingSkeleton variant="card" label="Loading integrations" />
			<LoadingSkeleton variant="card" label="Loading team access" />
			<LoadingSkeleton variant="card" label="Loading history and recovery" />
		</section>
	</main>
	<!-- eslint-enable svelte/no-at-html-tags -->
{:else if isInitialError}
	<main class="organization-detail organization-detail--unavailable">
		<ErrorState
			title="Organization could not be loaded"
			description={errorDescription}
			retry={() => accessQuery.refetch()}
		>
			{#snippet action()}<a
					class="organization-detail__back-link"
					href={resolve('/jafar/organizations')}>Back to organizations</a
				>{/snippet}
		</ErrorState>
	</main>
{:else if !preview && access}
	<!-- eslint-disable svelte/no-at-html-tags -->
	<main class="organization-detail">
		{#if isStaleData}
			<section class="organization-detail__stale-banner" role="status" aria-live="polite">
				<span class="organization-detail__stale-banner-icon" aria-hidden="true"
					>{@html alertIcon}</span
				>
				<div>
					<strong>Showing the last available organization information</strong>
					<p>The latest refresh failed, so this page may be out of date.</p>
				</div>
				<Button
					variant="secondary"
					variation="subtle"
					loading={accessQuery.isFetching}
					onclick={() => accessQuery.refetch()}
					>{accessQuery.isFetching ? 'Refreshing' : 'Try again'}</Button
				>
			</section>
		{/if}

		<nav class="organization-detail__breadcrumb" aria-label="Breadcrumb">
			<a href={resolve('/jafar/organizations')}
				><span aria-hidden="true">{@html arrowLeftIcon}</span> Organizations</a
			>
			<span aria-hidden="true">/</span>
			<span>{access.organization.name}</span>
		</nav>

		<header class="organization-detail__header">
			<div>
				<p class="organization-detail__eyebrow">Organization control room</p>
				<div class="organization-detail__heading-row">
					<h1>{access.organization.name}</h1>
					<Badge
						status={access.organization.lifecycle_status === 'active'
							? 'success'
							: access.organization.lifecycle_status === 'suspended' ||
								  access.organization.lifecycle_status === 'pending_closure' ||
								  access.organization.lifecycle_status === 'closed'
								? 'critical'
								: 'warning'}
						>{access.organization.lifecycle_status === 'pending_setup'
							? 'Needs review'
							: access.organization.lifecycle_status === 'pending_closure'
								? 'Closing'
								: access.organization.lifecycle_status === 'closed'
									? 'Closed'
									: access.organization.lifecycle_status}</Badge
					>
				</div>
				<p class="organization-detail__description">{access.organization.slug}</p>
			</div>
			<a class="organization-detail__back-link" href={resolve('/jafar/organizations')}
				>Back to directory</a
			>
		</header>

		{#if actionMessage}<p
				class="organization-detail__feedback organization-detail__feedback--success"
				role="status"
			>
				{actionMessage}
			</p>{/if}
		{#if actionError}<p
				class="organization-detail__feedback organization-detail__feedback--error"
				role="alert"
			>
				{actionError}
			</p>{/if}

		<section class="organization-detail__section" aria-labelledby="overview-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Overview</p>
				<h2 id="overview-title">What needs attention</h2>
				<p>Review organization identity, lifecycle, and the next safe action.</p>
			</div>

			<div class="organization-detail__overview-grid">
				<Card class="organization-detail__identity-card">
					<div class="organization-detail__card-icon">{@html buildingIcon}</div>
					<div>
						<p class="organization-detail__card-label">Organization</p>
						<h3>{access.organization.name}</h3>
						<p>{access.organization.slug}</p>
					</div>
					<dl>
						<div>
							<dt>Organization ID</dt>
							<dd>{access.organization.id}</dd>
						</div>
						<div>
							<dt>Package</dt>
							<dd>{access.package.display_name}</dd>
						</div>
					</dl>
				</Card>

				<Card class="organization-detail__lifecycle-card">
					<div
						class="organization-detail__card-icon organization-detail__card-icon--{access
							.organization.lifecycle_status === 'active'
							? 'success'
							: access.organization.lifecycle_status === 'pending_setup'
								? 'warning'
								: 'critical'}"
					>
						{@html access.organization.lifecycle_status === 'active'
							? checkIcon
							: access.organization.lifecycle_status === 'pending_setup'
								? alertIcon
								: access.organization.lifecycle_status === 'pending_closure'
									? clockIcon
									: lockIcon}
					</div>
					<div>
						<p class="organization-detail__card-label">Lifecycle</p>
						<h3>
							{access.organization.lifecycle_status === 'pending_setup'
								? 'Needs review'
								: access.organization.lifecycle_status === 'pending_closure'
									? 'Closing'
									: access.organization.lifecycle_status === 'closed'
										? 'Closed'
										: access.organization.lifecycle_status}
						</h3>
						<p>
							{access.organization.lifecycle_status === 'suspended'
								? 'New contractor actions are paused while records stay preserved.'
								: access.organization.lifecycle_status === 'pending_setup'
									? 'This legacy organization predates paid onboarding and needs a one-time review.'
									: access.organization.lifecycle_status === 'pending_closure'
										? 'Contractor access is blocked. Restore before the deadline or it deletes automatically.'
										: access.organization.lifecycle_status === 'closed'
											? 'This organization has been permanently deleted.'
											: 'Commercial access is currently allowed.'}
						</p>
					</div>
					<div class="organization-detail__status-line">
						{#if access.organization.lifecycle_status === 'pending_setup'}
							<LegacyReconcileActions organizationId={access.organization.id} />
						{:else}
							{#if access.organization.lifecycle_status !== 'pending_closure' && access.organization.lifecycle_status !== 'closed'}
								<LifecycleActions
									organizationId={access.organization.id}
									lifecycleStatus={access.organization.lifecycle_status}
								/>
							{/if}
							<ClosureActions
								organizationId={access.organization.id}
								organizationName={access.organization.name}
								lifecycleStatus={access.organization.lifecycle_status}
								closure={commercialQuery.data?.closure ?? null}
							/>
						{/if}
					</div>
				</Card>

				<Card class="organization-detail__next-card">
					<div class="organization-detail__card-icon organization-detail__card-icon--informative">
						{@html alertIcon}
					</div>
					<div>
						<p class="organization-detail__card-label">Next safe action</p>
						{#if access.organization.lifecycle_status === 'pending_setup'}
							<h3>One-time legacy review</h3>
							<p>Resolve the checklist below, then activate or suspend this organization.</p>
						{:else if access.organization.lifecycle_status === 'pending_closure'}
							<h3>Closing organization</h3>
							<p>
								Restore before the deadline shown above, or let the countdown finish and delete
								everything.
							</p>
						{:else if access.organization.lifecycle_status === 'closed'}
							<h3>Organization deleted</h3>
							<p>All records for this organization have been permanently removed.</p>
						{:else if access.organization.lifecycle_status === 'suspended'}
							<h3>Review before reactivating</h3>
							<p>Confirm the reason for suspension no longer applies before reactivating.</p>
						{:else if packagesCatalogQuery.isPending}
							<h3>Loading package versions</h3>
							<p>Published package versions are loading before the next commercial action.</p>
						{:else if access.billing.is_overdue && !access.billing.is_in_grace}
							<h3>Paid-through date is past grace</h3>
							<p>Review commercial eligibility before any further lifecycle change.</p>
						{:else if access.billing.is_in_grace}
							<h3>In grace period</h3>
							<p>Grace ends {formatDateTime(access.billing.grace_ends_at)}.</p>
						{:else}
							<h3>No owner action required</h3>
							<p>Lifecycle and commercial access are both clear.</p>
						{/if}
					</div>
				</Card>
			</div>
		</section>

		<section class="organization-detail__at-a-glance" aria-label="Organization status at a glance">
			<article>
				<span class="organization-detail__mini-icon">{@html calendarIcon}</span>
				<div>
					<p>Commercial access</p>
					<strong>{formatCalendarDate(access.billing.paid_through_date)}</strong>
					<small
						>{access.billing.is_in_grace
							? `In grace until ${formatDateTime(access.billing.grace_ends_at)}`
							: access.billing.is_overdue
								? 'Past grace'
								: 'Not in grace'}</small
					>
				</div>
			</article>
			<article>
				<span class="organization-detail__mini-icon">{@html shieldIcon}</span>
				<div>
					<p>Free access</p>
					{#if access.free_access.active}
						<strong
							>{access.free_access.active.access_until_date === null
								? 'Free forever'
								: `Free until ${formatCalendarDate(access.free_access.active.access_until_date)}`}</strong
						>
						{#if access.free_access.future}
							<small>Another grant is scheduled</small>
						{:else}
							<small>Managed in Commercial access below</small>
						{/if}
					{:else if access.free_access.future}
						<strong>Paid access</strong>
						<small
							>Free access starts {formatCalendarDate(access.free_access.future.starts_at)}</small
						>
					{:else}
						<strong>Paid access</strong>
						<small>Managed in Commercial access below</small>
					{/if}
				</div>
			</article>
			<article>
				<span class="organization-detail__mini-icon">{@html usersIcon}</span>
				<div>
					<p>Package status</p>
					<strong>{access.package.status}</strong>
					<small
						>{access.package.version_number
							? `Version ${access.package.version_number}`
							: 'Legacy assignment'}</small
					>
				</div>
			</article>
		</section>

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
							This organization still uses the legacy package column. Assigning a published version
							records an immutable billing baseline and unlocks free-access management.
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
								<Input id="legacy-assign-reason" label="Private reason" bind:value={legacyReason} />
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
									<td>{override?.is_legacy_import ? 'Legacy import' : (override?.reason ?? '—')}</td
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

		<section class="organization-detail__section" aria-labelledby="integrations-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Integrations</p>
				<h2 id="integrations-title">Effective provider readiness</h2>
			</div>
			<Card class="organization-detail__commercial-explainer">
				<EmailDomainActions organizationId={access.organization.id} />
			</Card>
			<Card class="organization-detail__commercial-explainer">
				<EmailSendingPauseActions organizationId={access.organization.id} />
			</Card>
			<Card class="organization-detail__commercial-explainer">
				<EmailReputationActions organizationId={access.organization.id} />
			</Card>
			<Card class="organization-detail__commercial-explainer">
				<EmailAllowanceActions organizationId={access.organization.id} />
			</Card>
			<Card class="organization-detail__commercial-explainer">
				<WebsiteChatAllowanceActions organizationId={access.organization.id} />
			</Card>
			<Card class="organization-detail__commercial-explainer">
				<WebsiteChatAuthorityActions organizationId={access.organization.id} />
			</Card>
			<Card class="organization-detail__commercial-explainer">
				<AutomationAuthorityActions organizationId={access.organization.id} />
			</Card>
		</section>

		<section class="organization-detail__section" aria-labelledby="team-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Team access</p>
				<h2 id="team-title">Read-only access review</h2>
				<p>
					Contractor owners and administrators manage their team. Jafar can inspect roles and
					administrator readiness, fix a support-case profile correction, and recover a locked-out
					administrator's login without silently changing permissions.
				</p>
			</div>
			<Card class="organization-detail__team-card">
				{#if teamQuery.isPending}
					<LoadingSkeleton variant="table" label="Loading team members" />
				{:else if teamQuery.isError}
					<ErrorState
						title="Team members could not be loaded"
						description={teamQuery.error instanceof Error
							? teamQuery.error.message
							: 'Team members could not be loaded. Try again.'}
						retry={() => teamQuery.refetch()}
					/>
				{:else}
					<TeamAccessActions
						organizationId={access.organization.id}
						members={teamQuery.data?.members ?? []}
					/>
					<div class="organization-detail__recovery-note">
						<span
							class="organization-detail__card-icon organization-detail__card-icon--{teamQuery.data
								?.has_administrator
								? 'success'
								: 'warning'}"
							>{@html teamQuery.data?.has_administrator ? checkIcon : alertIcon}</span
						>
						<div>
							<h3>Administrator readiness</h3>
							<p>
								{teamQuery.data?.has_administrator
									? 'At least one owner or admin can manage this organization.'
									: 'No owner or admin exists for this organization. Recovery is not built yet — coordinate with the contractor directly.'}
							</p>
						</div>
						<Badge status={teamQuery.data?.has_administrator ? 'success' : 'warning'}
							>{teamQuery.data?.has_administrator ? 'Ready' : 'Needs attention'}</Badge
						>
					</div>
				{/if}
			</Card>
		</section>

		<section class="organization-detail__section" aria-labelledby="attention-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Needs attention</p>
				<h2 id="attention-title">Open recovery items</h2>
				<p>Background work that has not succeeded yet for this organization.</p>
			</div>
			<Card class="organization-detail__history-card">
				{#if organizationOperationsQuery.isPending || (applicationId && applicationOperationsQuery.isPending)}
					<LoadingSkeleton variant="table" label="Loading open recovery items" />
				{:else if organizationOperationsQuery.isError || (applicationId && applicationOperationsQuery.isError)}
					<ErrorState
						title="Open recovery items could not be loaded"
						description={organizationOperationsQuery.error instanceof Error
							? organizationOperationsQuery.error.message
							: applicationOperationsQuery.error instanceof Error
								? applicationOperationsQuery.error.message
								: 'Open recovery items could not be loaded. Try again.'}
						retry={() => {
							organizationOperationsQuery.refetch();
							applicationOperationsQuery.refetch();
						}}
					/>
				{:else if attentionOperations.length === 0}
					<p class="organization-detail__muted">No open issues.</p>
				{:else}
					<div class="organization-detail__table-wrap">
						<table>
							<caption>Open recovery items</caption>
							<thead>
								<tr>
									<th scope="col">Type</th>
									<th scope="col">Status</th>
									<th scope="col">Attempts</th>
									<th scope="col">Updated</th>
									<th scope="col"><span class="organization-detail__sr-only">Open</span></th>
								</tr>
							</thead>
							<tbody>
								{#each attentionOperations as operation (operation.id)}
									<tr>
										<td
											>{OPERATION_TYPE_LABELS[operation.operation_type] ??
												operation.operation_type}</td
										>
										<td
											><Badge status="warning"
												>{OPERATION_STATUS_LABELS[operation.status] ?? operation.status}</Badge
											></td
										>
										<td>{operation.attempt_count}</td>
										<td>{formatDateTime(operation.updated_at)}</td>
										<td
											><a href={`${resolve('/jafar/operations')}?operation=${operation.id}`}
												>View in Operations</a
											></td
										>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{/if}
			</Card>
		</section>

		<section class="organization-detail__section" aria-labelledby="history-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">History and recovery</p>
				<h2 id="history-title">Owner-private activity</h2>
				<p>Every commercial and status change made from this screen, most recent first.</p>
			</div>
			<Card class="organization-detail__history-card">
				{#if historyQuery.isPending}
					<LoadingSkeleton variant="table" label="Loading activity history" />
				{:else if historyQuery.isError}
					<ErrorState
						title="Activity history could not be loaded"
						description={historyQuery.error instanceof Error
							? historyQuery.error.message
							: 'Activity history could not be loaded. Try again.'}
						retry={() => historyQuery.refetch()}
					/>
				{:else}
					<div class="organization-detail__table-wrap">
						<table>
							<caption>Activity history</caption>
							<thead>
								<tr>
									<th scope="col">Change</th>
									<th scope="col">By</th>
									<th scope="col">When</th>
								</tr>
							</thead>
							<tbody>
								{#each historyQuery.data?.events ?? [] as historyEvent (historyEvent.id)}
									<tr>
										<td
											>{HISTORY_EVENT_LABELS[historyEvent.event_type] ??
												historyEvent.event_type}</td
										>
										<td>{historyEvent.actor_email ?? 'Not recorded'}</td>
										<td>{formatDateTime(historyEvent.occurred_at)}</td>
									</tr>
								{:else}
									<tr><td colspan="3">No activity has been recorded yet.</td></tr>
								{/each}
							</tbody>
						</table>
					</div>
				{/if}
			</Card>
		</section>
	</main>
	<!-- eslint-enable svelte/no-at-html-tags -->
{:else}
	<!-- eslint-disable svelte/no-at-html-tags -->
	<main class="organization-detail">
		<nav class="organization-detail__breadcrumb" aria-label="Breadcrumb">
			<a href={resolve('/jafar/organizations')}
				><span aria-hidden="true">{@html arrowLeftIcon}</span> Organizations</a
			>
			<span aria-hidden="true">/</span>
			<span>{preview?.name}</span>
		</nav>

		<header class="organization-detail__header">
			<div>
				<p class="organization-detail__eyebrow">Organization control room</p>
				<div class="organization-detail__heading-row">
					<h1>{preview?.name}</h1>
					<Badge status={preview?.lifecycleTone}>{preview?.lifecycle}</Badge>
				</div>
				<p class="organization-detail__description">
					{preview?.slug} · Development scenario: {organizationDetailScenarioLabel(
						preview?.scenario ?? 'active'
					)}
				</p>
			</div>
			<a class="organization-detail__back-link" href={resolve('/jafar/organizations')}
				>Back to directory</a
			>
		</header>

		<section
			class="organization-detail__preview-notice"
			role="status"
			aria-label="Development preview"
		>
			<span aria-hidden="true">{@html shieldIcon}</span>
			<p>
				<strong>Development-only preview.</strong> This scenario is local to this screen, cannot change
				records, and is hidden from production.
			</p>
		</section>

		{#if preview?.warning}
			<section
				class="organization-detail__warning organization-detail__warning--{preview.warning.tone}"
				role="alert"
			>
				<span aria-hidden="true">{@html alertIcon}</span>
				<div>
					<strong>{preview.warning.title}</strong>
					<p>{preview.warning.detail}</p>
				</div>
			</section>
		{/if}

		<section class="organization-detail__section" aria-labelledby="overview-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Overview</p>
				<h2 id="overview-title">What needs attention</h2>
				<p>
					Review organization identity, lifecycle, administrator readiness, and the next safe
					action.
				</p>
			</div>

			<div class="organization-detail__overview-grid">
				<Card class="organization-detail__identity-card">
					<div class="organization-detail__card-icon">{@html buildingIcon}</div>
					<div>
						<p class="organization-detail__card-label">Organization</p>
						<h3>{preview?.name}</h3>
						<p>{preview?.slug}</p>
					</div>
					<dl>
						<div>
							<dt>Preview record</dt>
							<dd>{preview?.id}</dd>
						</div>
						<div>
							<dt>Scenario</dt>
							<dd>{organizationDetailScenarioLabel(preview?.scenario ?? 'active')}</dd>
						</div>
					</dl>
				</Card>

				<Card class="organization-detail__lifecycle-card">
					<div
						class="organization-detail__card-icon organization-detail__card-icon--{preview?.lifecycleTone}"
					>
						{@html preview?.lifecycleTone === 'success'
							? checkIcon
							: preview?.lifecycleTone === 'critical'
								? lockIcon
								: clockIcon}
					</div>
					<div>
						<p class="organization-detail__card-label">Lifecycle</p>
						<h3>{preview?.lifecycle}</h3>
						<p>
							{preview?.lifecycle === 'Suspended'
								? 'New contractor actions are paused while records stay preserved.'
								: 'Commercial access is currently allowed.'}
						</p>
					</div>
					<div class="organization-detail__status-line">
						<Badge status={preview?.setup.tone}>{preview?.setup.state}</Badge><span
							>{preview?.setup.detail}</span
						>
					</div>
				</Card>

				<Card class="organization-detail__next-card">
					<div class="organization-detail__card-icon organization-detail__card-icon--informative">
						{@html alertIcon}
					</div>
					<div>
						<p class="organization-detail__card-label">Next safe action</p>
						<h3>
							{preview?.warning ? 'Review before changing access' : 'No owner action required'}
						</h3>
						<p>
							{preview?.warning
								? preview.warning.detail
								: 'Commercial access, administrator readiness, and recovery state are all clear in this scenario.'}
						</p>
					</div>
					<span class="organization-detail__safe-label">No live actions yet</span>
				</Card>
			</div>
		</section>

		<section class="organization-detail__at-a-glance" aria-label="Organization status at a glance">
			<article>
				<span class="organization-detail__mini-icon">{@html calendarIcon}</span>
				<div>
					<p>Commercial access</p>
					<strong>{preview?.commercial.paidThrough}</strong><small
						>{preview?.commercial.grace}</small
					>
				</div>
			</article>
			<article>
				<span class="organization-detail__mini-icon">{@html usersIcon}</span>
				<div>
					<p>Administrator setup</p>
					<strong>{preview?.setup.state}</strong><small
						>{preview?.team[0].name} is the primary administrator</small
					>
				</div>
			</article>
			<article>
				<span class="organization-detail__mini-icon">{@html shieldIcon}</span>
				<div>
					<p>Recovery</p>
					<strong>{preview?.recovery.state}</strong><small>{preview?.recovery.detail}</small>
				</div>
			</article>
		</section>

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

		<section class="organization-detail__section" aria-labelledby="integrations-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Integrations</p>
				<h2 id="integrations-title">Effective provider readiness</h2>
				<p>
					Configured preferences and provider health remain separate. The state below is a safe
					development scenario, not a provider check.
				</p>
			</div>
			<div class="organization-detail__integration-grid">
				{#each preview?.integrations ?? [] as integration (integration.name)}
					<Card class="organization-detail__integration-card">
						<div class="organization-detail__integration-heading">
							<span
								class="organization-detail__card-icon organization-detail__card-icon--{integration.tone}"
								>{@html plugIcon}</span
							>
							<div>
								<h3>{integration.name}</h3>
								<Badge status={integration.tone}>{integration.state}</Badge>
							</div>
						</div>
						<p>{integration.detail}</p>
						<div class="organization-detail__integration-next">
							<span>Next safe step</span><strong>{integration.nextAction}</strong>
						</div>
					</Card>
				{/each}
			</div>
		</section>

		<section class="organization-detail__section" aria-labelledby="team-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Team access</p>
				<h2 id="team-title">Read-only access review</h2>
				<p>
					Contractor owners and administrators manage their team. Jafar can inspect effective access
					and recovery readiness without silently changing a role.
				</p>
			</div>
			<Card class="organization-detail__team-card">
				<div class="organization-detail__table-wrap">
					<table>
						<caption>Development-only team access preview</caption>
						<thead
							><tr
								><th scope="col">Team member</th><th scope="col">Role</th><th scope="col"
									>Effective access</th
								><th scope="col">Access note</th></tr
							></thead
						>
						<tbody
							>{#each preview?.team ?? [] as member (member.name)}<tr
									><td>{member.name}</td><td>{member.role}</td><td>{member.access}</td><td
										>{member.note}</td
									></tr
								>{/each}</tbody
						>
					</table>
				</div>
				<div class="organization-detail__recovery-note">
					<span class="organization-detail__card-icon organization-detail__card-icon--warning"
						>{@html alertIcon}</span
					>
					<div>
						<h3>Administrator recovery</h3>
						<p>
							Email recovery will require independent verification and identity reconfirmation when
							its secure workflow is built. Passwords and setup links are never shown here.
						</p>
					</div>
					<Badge status={preview?.setup.tone}>{preview?.setup.state}</Badge>
				</div>
			</Card>
		</section>

		<section class="organization-detail__section" aria-labelledby="history-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">History and recovery</p>
				<h2 id="history-title">Owner-private activity</h2>
				<p>
					History remains sanitized: it never includes passwords, credentials, setup links, or raw
					provider evidence.
				</p>
			</div>
			<div class="organization-detail__history-grid">
				<Card class="organization-detail__history-card">
					<div class="organization-detail__history-heading">
						<span class="organization-detail__card-icon">{@html historyIcon}</span>
						<div>
							<h3>Recent history</h3>
							<p>Representative development records</p>
						</div>
					</div>
					<ul class="organization-detail__history-list">
						{#each preview?.history ?? [] as item (`${item.at}-${item.title}`)}<li>
								<span
									class="organization-detail__history-dot organization-detail__history-dot--{item.tone}"
									aria-hidden="true"
								></span>
								<div>
									<strong>{item.title}</strong>
									<p>{item.detail}</p>
								</div>
								<time>{item.at}</time>
							</li>{/each}
					</ul>
				</Card>
				<Card class="organization-detail__recovery-card">
					<div
						class="organization-detail__card-icon organization-detail__card-icon--{preview?.recovery
							.tone}"
					>
						{@html clockIcon}
					</div>
					<div>
						<p class="organization-detail__card-label">Recovery state</p>
						<h3>{preview?.recovery.state}</h3>
						<p>{preview?.recovery.detail}</p>
					</div>
					<AlertDialog.Root bind:open={confirmationOpen}>
						<AlertDialog.Trigger>
							{#snippet child({ props })}<Button {...props} variant="secondary" variation="subtle"
									>Preview confirmation</Button
								>{/snippet}
						</AlertDialog.Trigger>
						<AlertDialog.Portal>
							<AlertDialog.Overlay class="organization-detail__dialog-overlay" />
							<AlertDialog.Content class="organization-detail__dialog-content">
								<AlertDialog.Title level={2}>Review a recovery action</AlertDialog.Title>
								<AlertDialog.Description
									>This is a development-only confirmation preview. It cannot retry, acknowledge, or
									change any organization record.</AlertDialog.Description
								>
								<dl class="organization-detail__dialog-summary">
									<div>
										<dt>Organization</dt>
										<dd>{preview?.name}</dd>
									</div>
									<div>
										<dt>Current state</dt>
										<dd>{preview?.recovery.state}</dd>
									</div>
									<div>
										<dt>Future live safeguard</dt>
										<dd>Reason and a secure audit record</dd>
									</div>
								</dl>
								<div class="organization-detail__dialog-actions">
									<AlertDialog.Action
										>{#snippet child({ props })}<Button {...props}>I understand</Button
											>{/snippet}</AlertDialog.Action
									><AlertDialog.Cancel
										>{#snippet child({ props })}<Button
												{...props}
												variant="secondary"
												variation="subtle">Close</Button
											>{/snippet}</AlertDialog.Cancel
									>
								</div>
							</AlertDialog.Content>
						</AlertDialog.Portal>
					</AlertDialog.Root>
				</Card>
			</div>
		</section>
	</main>
	<!-- eslint-enable svelte/no-at-html-tags -->
{/if}

<style lang="scss">
	.organization-detail {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}
	.organization-detail--unavailable {
		max-width: 640px;
		margin: var(--space-largest) auto;
	}
	.organization-detail__stale-banner {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.organization-detail__stale-banner-icon {
		display: inline-flex;
		flex: 0 0 auto;
	}
	.organization-detail__stale-banner-icon :global(svg) {
		width: var(--typography--fontSize-largest);
		height: var(--typography--fontSize-largest);
	}
	.organization-detail__stale-banner div {
		flex: 1;
	}
	.organization-detail__stale-banner strong {
		display: block;
		color: inherit;
	}
	.organization-detail__stale-banner p {
		margin: var(--space-smaller) 0 0;
		color: inherit;
	}
	.organization-detail__feedback {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__feedback--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.organization-detail__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.organization-detail__breadcrumb {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__breadcrumb a,
	.organization-detail__back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-interactive);
		font-weight: 600;
		text-decoration: underline;
		text-underline-offset: var(--space-smaller);
	}
	.organization-detail__breadcrumb a:hover,
	.organization-detail__back-link:hover {
		color: var(--color-interactive--hover);
	}
	.organization-detail__breadcrumb a:focus-visible,
	.organization-detail__back-link:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.organization-detail__breadcrumb :global(svg) {
		width: 16px;
		height: 16px;
	}
	.organization-detail__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-large);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.organization-detail__loading-heading {
		display: grid;
		gap: var(--space-small);
		width: min(560px, 60vw);
	}
	.organization-detail__loading-heading :global(.skeleton--heading) {
		width: min(360px, 80%);
	}
	.organization-detail__loading-heading :global(.skeleton--text) {
		width: min(520px, 100%);
	}
	.organization-detail__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1,
	h2,
	h3,
	p {
		margin: 0;
	}
	h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
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
	.organization-detail__heading-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-base);
	}
	.organization-detail__description,
	.organization-detail__section-heading > p:last-child {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.organization-detail__back-link {
		min-height: 40px;
		white-space: nowrap;
	}
	.organization-detail__preview-notice,
	.organization-detail__warning {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
	}
	.organization-detail__preview-notice {
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.organization-detail__preview-notice > span,
	.organization-detail__warning > span {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		width: var(--space-large);
		height: var(--space-large);
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-informative);
	}
	.organization-detail__preview-notice :global(svg),
	.organization-detail__warning :global(svg) {
		width: 16px;
		height: 16px;
	}
	.organization-detail__warning {
		color: var(--warning-text);
		background: var(--warning-surface);
	}
	.organization-detail__warning--warning {
		--warning-text: var(--color-warning--onSurface);
		--warning-surface: var(--color-warning--surface);
	}
	.organization-detail__warning--critical {
		--warning-text: var(--color-critical--onSurface);
		--warning-surface: var(--color-critical--surface);
	}
	.organization-detail__warning--informative {
		--warning-text: var(--color-informative--onSurface);
		--warning-surface: var(--color-informative--surface);
	}
	.organization-detail__warning--warning > span {
		background: var(--color-warning);
	}
	.organization-detail__warning--critical > span {
		background: var(--color-critical);
	}
	.organization-detail__warning--informative > span {
		background: var(--color-informative);
	}
	.organization-detail__warning p {
		margin-top: var(--space-smaller);
		line-height: var(--typography--lineHeight-base);
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
	.organization-detail__overview-grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__identity-card,
	.organization-detail__lifecycle-card,
	.organization-detail__next-card {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__card-icon,
	.organization-detail__mini-icon {
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
	.organization-detail__card-icon--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.organization-detail__card-icon--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.organization-detail__card-icon--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.organization-detail__card-icon--inactive {
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
	}
	.organization-detail__card-label {
		margin-bottom: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	.organization-detail__identity-card p:last-child,
	.organization-detail__lifecycle-card p:last-child,
	.organization-detail__next-card p:last-child {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail dl {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-small);
		margin: 0;
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail dd {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		overflow-wrap: anywhere;
	}
	.organization-detail__status-line {
		display: grid;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__status-line > span {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.organization-detail__safe-label {
		width: fit-content;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__at-a-glance {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__at-a-glance :global(.skeleton--card) {
		height: 104px;
	}
	.organization-detail__loading-sections {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__loading-sections :global(.skeleton--card) {
		height: 220px;
	}
	.organization-detail__at-a-glance article {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.organization-detail__mini-icon {
		flex: 0 0 32px;
		width: 32px;
		height: 32px;
	}
	.organization-detail__mini-icon :global(svg) {
		width: 18px;
		height: 18px;
	}
	.organization-detail__at-a-glance div {
		min-width: 0;
	}
	.organization-detail__at-a-glance p,
	.organization-detail__at-a-glance small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__at-a-glance strong,
	.organization-detail__at-a-glance small {
		display: block;
	}
	.organization-detail__at-a-glance strong {
		margin: var(--space-smallest) 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__commercial-grid,
	.organization-detail__history-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__commercial-card,
	.organization-detail__recovery-card {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__commercial-card p:last-child,
	.organization-detail__recovery-card p:last-child {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__commercial-explainer {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.organization-detail__commercial-explainer > div {
		flex: 1;
		min-width: 0;
		display: grid;
		gap: var(--space-base);
	}
	.organization-detail :global(.organization-detail__commercial-explainer h3),
	.organization-detail__history-heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.organization-detail__commercial-explainer p,
	.organization-detail__history-heading p {
		max-width: 78ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__integration-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__integration-card {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__integration-heading,
	.organization-detail__history-heading {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
	}
	.organization-detail__integration-heading h3 {
		margin-bottom: var(--space-small);
		font-size: var(--typography--fontSize-large);
	}
	.organization-detail :global(.organization-detail__integration-card > p) {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__integration-next {
		display: grid;
		gap: var(--space-smallest);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__integration-next span {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__integration-next strong {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__team-card {
		display: grid;
		gap: var(--space-large);
	}
	.organization-detail__table-wrap {
		overflow-x: auto;
	}
	.organization-detail table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		text-align: left;
	}
	.organization-detail caption {
		padding-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: left;
	}
	.organization-detail th,
	.organization-detail td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		vertical-align: top;
	}
	.organization-detail th {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.organization-detail td:first-child {
		color: var(--color-heading);
		font-weight: 700;
	}
	.organization-detail__recovery-note {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border-radius: var(--radius-small);
		background: var(--color-surface--background--subtle);
	}
	.organization-detail__recovery-note > div {
		flex: 1;
		min-width: 0;
	}
	.organization-detail__recovery-note h3 {
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__recovery-note p {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.organization-detail__history-card {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__muted {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		margin: 0;
	}
	.organization-detail__sr-only {
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
	.organization-detail__history-list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.organization-detail__history-list li {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) auto;
		align-items: start;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__history-dot {
		width: var(--space-small);
		height: var(--space-small);
		margin-top: var(--space-smaller);
		border-radius: var(--radius-circle);
		background: var(--history-color);
	}
	.organization-detail__history-dot--success {
		--history-color: var(--color-success);
	}
	.organization-detail__history-dot--warning {
		--history-color: var(--color-warning);
	}
	.organization-detail__history-dot--critical {
		--history-color: var(--color-critical);
	}
	.organization-detail__history-dot--informative {
		--history-color: var(--color-informative);
	}
	.organization-detail__history-dot--inactive {
		--history-color: var(--color-inactive);
	}
	.organization-detail__history-list strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__history-list p {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.organization-detail__history-list time {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		white-space: nowrap;
	}
	.organization-detail :global(.organization-detail__recovery-card > .button) {
		width: fit-content;
		margin-top: auto;
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
	.organization-detail__capabilities {
		flex-direction: column;
	}
	:global(.organization-detail__dialog-overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}
	:global(.organization-detail__dialog-content) {
		position: fixed;
		top: 50%;
		left: 50%;
		z-index: var(--elevation-modal);
		display: grid;
		gap: var(--space-base);
		width: min(calc(100vw - var(--space-large) * 2), 480px);
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		transform: translate(-50%, -50%);
	}
	:global(.organization-detail__dialog-content [data-slot='alert-dialog-title']) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tightest);
	}
	:global(.organization-detail__dialog-content [data-slot='alert-dialog-description']) {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__dialog-summary {
		grid-template-columns: 1fr;
		gap: var(--space-base);
		padding-top: var(--space-base);
	}
	.organization-detail__dialog-summary dd {
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 1100px) {
		.organization-detail__overview-grid,
		.organization-detail__integration-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 767px) {
		.organization-detail__header {
			flex-direction: column;
		}
		.organization-detail__at-a-glance {
			grid-template-columns: 1fr;
		}
		.organization-detail__loading-heading {
			width: 100%;
		}
	}
	@media (max-width: 639px) {
		h1 {
			font-size: 28px;
		}
		.organization-detail__overview-grid,
		.organization-detail__commercial-grid,
		.organization-detail__integration-grid,
		.organization-detail__history-grid {
			grid-template-columns: 1fr;
		}
		.organization-detail__loading-sections {
			grid-template-columns: 1fr;
		}
		.organization-detail__commercial-explainer,
		.organization-detail__recovery-note {
			flex-direction: column;
		}
		.organization-detail__history-list li {
			grid-template-columns: auto minmax(0, 1fr);
		}
		.organization-detail__history-list time {
			grid-column: 2;
		}
		.organization-detail__back-link {
			min-height: auto;
		}
	}
</style>
