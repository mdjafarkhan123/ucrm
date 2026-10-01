import { httpError } from '$lib/http-error';
// Settings reads and writes. Business Profile, Branding, and Business Hours are three independently
// saved sections of one organization record — each carries its own revision so a stale save only ever
// names the section that actually collided.

import type { CatalogItem, PricingCategory } from '$lib/quotes/api';
import type { CustomStage } from '$lib/pipeline/stages';
import type { InactivityDays } from '$lib/pipeline/freshness';
import { finishFileUpload, startFileUpload } from '$lib/files/api';
import { uploadAttachmentFile } from '$lib/collaboration/api';

export type SettingsMember = { name: string | null; email: string | null; role: string };

export type SettingsHome = {
	member: SettingsMember;
	organization: { name: string };
	permissions: {
		business_edit: boolean;
		team_manage: boolean;
		communications_manage: boolean;
		snippets_manage: boolean;
		taxes_manage: boolean;
		price_book_manage: boolean;
		checklists_manage: boolean;
		forms_manage: boolean;
		reviews_manage: boolean;
		quotes_manage: boolean;
		invoices_manage: boolean;
		payments_manage: boolean;
		automations_view: boolean;
	};
	readiness: {
		business_profile: { complete: boolean; missing: Array<'name' | 'timezone' | 'currency'> };
		business_hours_set: boolean;
		sms_registration: { readiness_state: string } | null;
		/** Nobody is chosen for website inquiry alerts, so only the account owner gets them. */
		inquiry_alerts_owner_only: boolean;
	};
};

export const settingsHomeKey = ['settings', 'home'] as const;

export async function fetchSettingsHome(): Promise<SettingsHome> {
	const response = await fetch('/api/settings');
	if (!response.ok) throw httpError(response, 'Settings could not be loaded.');
	return response.json();
}

export type SettingsEditor = { name: string | null; at: string | null } | null;

export type BusinessProfile = {
	name: string;
	trade: string | null;
	phone: string | null;
	website: string | null;
	description: string | null;
	address_line1: string | null;
	address_line2: string | null;
	city: string | null;
	region: string | null;
	postal_code: string | null;
	country_code: string | null;
	address_is_public: boolean;
	timezone: string;
	locale: string;
	currency_code: string;
	timezone_confirmed: boolean;
	currency_confirmed: boolean;
	/** Whether the address has resolved to real coordinates yet — the service area radius stays unusable until it has. */
	location_ready: boolean;
	service_area_radius_miles: number | null;
	revision: number;
	last_editor: SettingsEditor;
};

export type BusinessBranding = {
	brand_color: string | null;
	logo_url: string | null;
	revision: number;
	last_editor: SettingsEditor;
};

export type BusinessHourPeriod = {
	weekday: number;
	period_index: number;
	is_open: boolean;
	is_open_24h: boolean;
	opens_at: string | null;
	closes_at: string | null;
};

export type BusinessHours = {
	mode: 'not_configured' | 'weekly' | 'appointment_only';
	periods: BusinessHourPeriod[];
	revision: number;
	last_editor: SettingsEditor;
};

export type SettingsBusiness = {
	member: SettingsMember;
	permissions: { view: boolean; edit: boolean };
	profile: BusinessProfile;
	branding: BusinessBranding;
	hours: BusinessHours;
	readiness: {
		profile: { complete: boolean; missing: Array<'name' | 'timezone' | 'currency'> };
		hours_set: boolean;
	};
	currency_locked: boolean;
};

export const settingsBusinessKey = ['settings', 'business'] as const;

export async function fetchSettingsBusiness(): Promise<SettingsBusiness> {
	const response = await fetch('/api/settings/business');
	if (!response.ok) throw httpError(response, 'Business settings could not be loaded.');
	return response.json();
}

// Every save can come back as an outright error (validation, permission, rate limit) or as a 409 naming
// the person who saved first. The page tells those apart by status rather than by throwing for both, so
// a stale save can offer "someone else just changed this" instead of a generic failure banner.
export type SettingsSaveConflict = {
	conflict: true;
	editor_name: string | null;
	edited_at: string | null;
};

// Carries the server's per-field messages alongside the generic banner text, for a section (like Payments)
// whose fields can fail Zod validation -- a toggle can't, so no earlier section needed this read.
export type SettingsWriteError = Error & { status?: number; fieldErrors?: Record<string, string> };

async function saveSection<T>(url: string, body: unknown): Promise<T | SettingsSaveConflict> {
	const response = await fetch(url, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (response.status === 409) {
		return {
			conflict: true,
			editor_name: result.editor_name ?? null,
			edited_at: result.edited_at ?? null
		};
	}
	if (!response.ok) {
		const error = httpError(
			response,
			result.error ?? 'That could not be saved.'
		) as SettingsWriteError;
		error.fieldErrors = result.field_errors ?? {};
		throw error;
	}
	return result as T;
}

export type SaveResult = {
	profile_revision: number;
	branding_revision: number;
	hours_revision: number;
};

export function saveBusinessProfile(
	body: Record<string, unknown>
): Promise<SaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/business/profile', body);
}

export type ServiceAreaSaveResult = {
	status: 'saved';
	profile_revision: number;
	service_area_radius_miles: number;
};

export function saveServiceAreaRadius(
	body: Record<string, unknown>
): Promise<ServiceAreaSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/business/service-area', body);
}

export function saveBusinessHours(
	body: Record<string, unknown>
): Promise<SaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/business/hours', body);
}

export function saveBranding(
	body: Record<string, unknown>
): Promise<SaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/branding', body);
}

// Settings → Pipeline. Its own read and its own revision, apart from the three Business Profile sections
// above — this preference never touches business identity, so a save here can never collide with one there.
export type SettingsPipeline = {
	permissions: { view: boolean; edit: boolean };
	pipeline: {
		detailed_assessment_stages: boolean;
		inactivity_days: InactivityDays;
		stages: CustomStage[];
		revision: number;
		last_editor: SettingsEditor;
	};
};

export const settingsPipelineKey = ['settings', 'pipeline'] as const;

export async function fetchSettingsPipeline(): Promise<SettingsPipeline> {
	const response = await fetch('/api/settings/pipeline');
	if (!response.ok) throw httpError(response, 'Pipeline settings could not be loaded.');
	return response.json();
}

export type PipelineSaveResult = {
	status: 'saved';
	pipeline_revision: number;
	pipeline_detailed_assessment_stages: boolean;
};

export function savePipelineSettings(
	body: Record<string, unknown>
): Promise<PipelineSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/pipeline', body);
}

// How many cards a custom stage holds. Asked when somebody reaches for the stage's remove button, never
// with the page.
export const pipelineStageCardCountKey = (stageId: string) =>
	['settings', 'pipeline', 'stage-cards', stageId] as const;

export async function fetchPipelineStageCardCount(
	stageId: string
): Promise<{ card_count: number }> {
	const response = await fetch(`/api/settings/pipeline/stages/${stageId}`);
	if (!response.ok) throw httpError(response, 'This stage could not be checked.');
	return response.json();
}

// Where a switched-off stage's cards go: another custom stage's id, 'built_in' for each card's own
// built-in stage, or null when the stage is empty and nobody needed asking.
export type StageCardDestination = string | null;

export type DisableStageResult =
	| { status: 'disabled'; pipeline_revision: number; moved_count: number }
	// Cards arrived in the stage after the dialog counted it, so the question has to be asked after all.
	| { needsDestination: true; card_count: number }
	| SettingsSaveConflict;

export async function disablePipelineStage(
	stageId: string,
	body: { expected_revision: number; destination: StageCardDestination }
): Promise<DisableStageResult> {
	const response = await fetch(`/api/settings/pipeline/stages/${stageId}/disable`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (response.status === 409 && result.reason === 'needs_destination') {
		return { needsDestination: true, card_count: result.card_count ?? 0 };
	}
	if (response.status === 409) {
		return {
			conflict: true,
			editor_name: result.editor_name ?? null,
			edited_at: result.edited_at ?? null
		};
	}
	if (!response.ok) {
		const error = httpError(
			response,
			result.field_errors?.form ?? result.error ?? 'That stage could not be removed.'
		) as SettingsWriteError;
		error.fieldErrors = result.field_errors ?? {};
		throw error;
	}
	return result;
}

// Settings → Contact matching. Its own read and its own revision, like Pipeline: HighLevel's Contact
// deduplication preference — which contact wins when a website chat or form's phone and email belong to two
// different clients.
export type ContactMatchPriority = 'email' | 'phone';

export type SettingsContactMatching = {
	permissions: { view: boolean; edit: boolean };
	contact_matching: {
		priority: ContactMatchPriority;
		revision: number;
		last_editor: SettingsEditor;
	};
};

export const settingsContactMatchingKey = ['settings', 'contact-matching'] as const;

export async function fetchSettingsContactMatching(): Promise<SettingsContactMatching> {
	const response = await fetch('/api/settings/contact-matching');
	if (!response.ok) throw httpError(response, 'Contact matching settings could not be loaded.');
	return response.json();
}

export type ContactMatchingSaveResult = {
	status: 'saved';
	contact_match_revision: number;
	contact_match_priority: ContactMatchPriority;
};

export function saveContactMatchingSettings(
	body: Record<string, unknown>
): Promise<ContactMatchingSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/contact-matching', body);
}

export function isSaveConflict(result: unknown): result is SettingsSaveConflict {
	return (
		typeof result === 'object' &&
		result !== null &&
		(result as SettingsSaveConflict).conflict === true
	);
}

// A logo now goes through the shared File Manager pipeline (scan + thumbnail worker) like every other
// upload, so this just starts and hands off the upload -- there is no logo_url to return. The file
// promotes organization_settings.logo_object_key itself once it clears the safety check; the caller polls
// for that the same way RecordFilesCard.svelte waits for any other upload to appear.
export async function uploadOrganizationLogo(file: File, organizationId: string): Promise<void> {
	const started = await startFileUpload(file, {
		originType: 'organization',
		originId: organizationId,
		originRole: 'logo'
	});
	await uploadAttachmentFile(started.upload_url, file);
	await finishFileUpload(started.file.id);
}

export async function removeOrganizationLogo(): Promise<{
	branding_revision: number;
	logo_url: null;
}> {
	const response = await fetch('/api/settings/branding/logo', { method: 'DELETE' });
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw httpError(response, result.error ?? 'That logo could not be removed.');
	return result;
}

export const WEEKDAY_LABELS = [
	'Sunday',
	'Monday',
	'Tuesday',
	'Wednesday',
	'Thursday',
	'Friday',
	'Saturday'
];

// Settings → Taxes. Owner/administrator only — the whole destination is hidden from every other role, so
// there is no separate view/edit split the way Business Profile has one.
export type TaxRate = {
	id: string;
	name: string;
	/** 8.25% is 825. */
	rate_basis_points: number;
	is_active: boolean;
	revision: number;
};

export type TaxDefault = {
	source: 'not_configured' | 'rate' | 'no_tax';
	rate_id: string | null;
	revision: number;
	last_editor: SettingsEditor;
};

export type SettingsTaxes = {
	rates: TaxRate[];
	default: TaxDefault;
};

export const settingsTaxesKey = ['settings', 'taxes'] as const;

// The HTTP status a read was refused with, so the shared query-client retry can give up immediately on a
// 403/404 instead of retrying a denial that will never succeed — see query-client.ts's shouldRetry.
export type SettingsReadError = Error & { status?: number };

export async function fetchSettingsTaxes(): Promise<SettingsTaxes> {
	const response = await fetch('/api/settings/taxes');
	if (!response.ok) {
		const error = new Error('Taxes could not be loaded.') as SettingsReadError;
		error.status = response.status;
		throw error;
	}
	return response.json();
}

// The active-rate picker a Quote or Property editor uses — open to anyone who can price a quote or manage a
// property, not just owner/admin the way the Taxes destination itself is.
export type TaxPickerRate = { id: string; name: string; rate_basis_points: number };

export type TaxPickerResolved = {
	source: 'not_configured' | 'business_default' | 'property_default';
	name: string | null;
	rate_basis_points: number;
	rate_id: string | null;
};

export type TaxPicker = {
	rates: TaxPickerRate[];
	business_default: TaxPickerResolved;
	/** Only present when a `propertyId` was passed — a bare Property has nothing to inherit from itself. */
	property_default: TaxPickerResolved | null;
};

export const taxPickerKey = (propertyId?: string) => [
	'settings',
	'taxes',
	'picker',
	propertyId ?? null
];

export async function fetchTaxPicker(propertyId?: string): Promise<TaxPicker> {
	const url = propertyId
		? `/api/settings/taxes/picker?property_id=${encodeURIComponent(propertyId)}`
		: '/api/settings/taxes/picker';
	const response = await fetch(url);
	if (!response.ok) throw httpError(response, 'Tax options could not be loaded.');
	return response.json();
}

// The rate commands (create/update/active/delete) refuse by throwing rather than returning the
// {conflict:true} shape saveSection expects below — 'reason' carries 'stale' or nothing, the way Quotes'
// write errors already work, so this mirrors that pattern instead.
export type TaxWriteError = Error & { fieldErrors?: Record<string, string>; reason?: string };

async function taxRequest<T>(
	url: string,
	method: string,
	body: unknown,
	fallback: string
): Promise<T> {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as TaxWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return response.json();
}

export function createTaxRate(body: { name: string; rate_basis_points: number }): Promise<TaxRate> {
	return taxRequest('/api/settings/taxes', 'POST', body, 'That tax rate could not be saved.');
}

export function updateTaxRate(
	id: string,
	body: { expected_revision: number; name: string; rate_basis_points: number }
): Promise<TaxRate> {
	return taxRequest(
		`/api/settings/taxes/${id}`,
		'PATCH',
		body,
		'That tax rate could not be saved.'
	);
}

export function setTaxRateActive(
	id: string,
	body: { expected_revision: number; is_active: boolean }
): Promise<TaxRate> {
	return taxRequest(
		`/api/settings/taxes/${id}/active`,
		'PATCH',
		body,
		'That tax rate could not be changed.'
	);
}

export function deleteTaxRate(
	id: string,
	body: { expected_revision: number }
): Promise<{ status: 'deleted'; id: string }> {
	return taxRequest(
		`/api/settings/taxes/${id}`,
		'DELETE',
		body,
		'That tax rate could not be deleted.'
	);
}

export async function fetchTaxRatePropertyCount(id: string): Promise<number> {
	const response = await fetch(`/api/settings/taxes/${id}/property-count`);
	if (!response.ok) throw httpError(response, 'That could not be checked.');
	const result = await response.json();
	return result.count as number;
}

export async function fetchTaxDefaultPropertyCount(): Promise<number> {
	const response = await fetch('/api/settings/taxes/default/property-count');
	if (!response.ok) throw httpError(response, 'That could not be checked.');
	const result = await response.json();
	return result.count as number;
}

export type TaxDefaultSaveResult = {
	status: 'saved';
	tax_revision: number;
	tax_default_source: 'rate' | 'no_tax';
	tax_default_rate_id: string | null;
};

export function saveTaxDefault(body: {
	expected_revision: number;
	source: 'rate' | 'no_tax';
	rate_id: string | null;
}): Promise<TaxDefaultSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/taxes/default', body);
}

// A short, curated list — the currencies a small field-service business is actually likely to invoice in.
// Not a claim to cover every ISO 4217 code.
export const COMMON_CURRENCIES = [
	{ code: 'USD', label: 'US Dollar' },
	{ code: 'CAD', label: 'Canadian Dollar' },
	{ code: 'GBP', label: 'British Pound' },
	{ code: 'EUR', label: 'Euro' },
	{ code: 'AUD', label: 'Australian Dollar' },
	{ code: 'NZD', label: 'New Zealand Dollar' },
	{ code: 'PKR', label: 'Pakistani Rupee' },
	{ code: 'INR', label: 'Indian Rupee' },
	{ code: 'AED', label: 'UAE Dirham' },
	{ code: 'SAR', label: 'Saudi Riyal' }
];

// Settings → Price Book. Owner/administrator only, like Taxes. Reads the same `catalog_items` table and
// `/api/catalog-items` list the Quote/Request picker already uses — see `$lib/quotes/api.ts` for the
// shared `CatalogItem` shape and list fetch. This file only adds what management needs on top: the
// single-item fetch that resolves a last editor, and the three revision-protected writes.
export type PriceBookItem = CatalogItem & { last_editor: SettingsEditor };

export async function fetchPriceBookItem(id: string): Promise<PriceBookItem> {
	const response = await fetch(`/api/catalog-items/${id}`);
	if (!response.ok) throw httpError(response, 'That item could not be loaded.');
	const result = await response.json();
	return result.item;
}

export type PriceBookWriteError = Error & { fieldErrors?: Record<string, string>; reason?: string };

async function priceBookRequest<T>(
	url: string,
	method: string,
	body: unknown,
	fallback: string
): Promise<T> {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as PriceBookWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return response.json();
}

export type PriceBookItemInput = {
	category: PricingCategory;
	name: string;
	description?: string | null;
	unit_label?: string | null;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
	is_labor: boolean;
};

export type PriceBookWriteResult = { id: string; name: string; revision: number };

export function createPriceBookItem(input: PriceBookItemInput): Promise<PriceBookWriteResult> {
	return priceBookRequest(
		'/api/settings/price-book',
		'POST',
		input,
		'That item could not be saved.'
	);
}

export function updatePriceBookItem(
	id: string,
	input: PriceBookItemInput & { expected_revision: number }
): Promise<PriceBookWriteResult> {
	return priceBookRequest(
		`/api/settings/price-book/${id}`,
		'PATCH',
		input,
		'That item could not be saved.'
	);
}

export function deletePriceBookItem(
	id: string,
	body: { expected_revision: number }
): Promise<{ status: 'deleted'; id: string }> {
	return priceBookRequest(
		`/api/settings/price-book/${id}`,
		'DELETE',
		body,
		'That item could not be deleted.'
	);
}

// Settings → Quote Settings. Owner/administrator only, like Taxes and Price Book. Four sections, each with
// its own revision — a stale save in one never blocks another. Target margin's `basis_points` is absent
// (not null) for a viewer without cost/profit permission, matching the API's own redaction shape.
export type QuoteTerms = { terms: string | null; revision: number; last_editor: SettingsEditor };

export type QuoteRepresentative = {
	enabled: boolean;
	name: string | null;
	title: string | null;
	signature_url: string | null;
	revision: number;
	last_editor: SettingsEditor;
};

export type QuoteTargetMargin = {
	basis_points?: number;
	revision: number;
	last_editor: SettingsEditor;
};

export type QuoteSignaturePolicy = {
	require_customer_signature: boolean;
	revision: number;
	last_editor: SettingsEditor;
};

export type SettingsQuotes = {
	permissions: { manage: boolean; view_cost: boolean };
	terms: QuoteTerms;
	representative: QuoteRepresentative;
	target_margin: QuoteTargetMargin;
	signature_policy: QuoteSignaturePolicy;
};

export const settingsQuotesKey = ['settings', 'quotes'] as const;

export async function fetchSettingsQuotes(): Promise<SettingsQuotes> {
	const response = await fetch('/api/settings/quotes');
	if (!response.ok) {
		const error = new Error('Quote settings could not be loaded.') as SettingsReadError;
		error.status = response.status;
		throw error;
	}
	return response.json();
}

export type QuoteTermsSaveResult = {
	status: 'saved';
	quote_terms_revision: number;
	quote_terms: string | null;
};

export function saveQuoteTerms(body: {
	expected_revision: number;
	terms: string;
}): Promise<QuoteTermsSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/quotes/terms', body);
}

export type QuoteRepresentativeSaveResult = {
	revision: number;
	enabled: boolean;
	name: string | null;
	title: string | null;
	signature_url: string | null;
};

// `signature_object_key`, `signature_image`, and `remove_signature` are mutually exclusive; omitting all
// three leaves whatever signature is already saved untouched (the route re-reads it — see its own comment
// on why the browser can never resend the key itself).
export function saveQuoteRepresentative(body: {
	expected_revision: number;
	enabled: boolean;
	name: string;
	title: string;
	signature_object_key?: string;
	signature_image?: string;
	remove_signature?: boolean;
}): Promise<QuoteRepresentativeSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/quotes/representative', body);
}

// Same two-step flow as the logo: presign, PUT the bytes, then hand the object key to
// saveQuoteRepresentative. Nothing is committed until that save runs.
export async function uploadQuoteRepresentativeSignature(
	file: File
): Promise<{ object_key: string }> {
	const presignResponse = await fetch('/api/settings/quotes/representative/signature-upload', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ file_name: file.name, mime_type: file.type, size_bytes: file.size })
	});
	const presign = await presignResponse.json().catch(() => ({}));
	if (!presignResponse.ok)
		throw httpError(presignResponse, presign.error ?? 'That signature could not be uploaded.');

	const putResponse = await fetch(presign.upload_url, {
		method: 'PUT',
		headers: { 'content-type': file.type },
		body: file
	});
	if (!putResponse.ok) throw httpError(putResponse, 'That signature could not be uploaded.');

	return { object_key: presign.object_key as string };
}

export type QuoteTargetMarginSaveResult = {
	status: 'saved';
	quote_target_margin_revision: number;
	quote_target_margin_basis_points: number | null;
};

export function saveQuoteTargetMargin(body: {
	expected_revision: number;
	margin_basis_points: number | null;
}): Promise<QuoteTargetMarginSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/quotes/target-margin', body);
}

export type QuoteSignaturePolicySaveResult = {
	status: 'saved';
	quote_signature_policy_revision: number;
	quote_require_customer_signature: boolean;
};

export function saveQuoteSignaturePolicy(body: {
	expected_revision: number;
	require_customer_signature: boolean;
}): Promise<QuoteSignaturePolicySaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/quotes/signature-policy', body);
}

// Settings → Invoices (Contractor Settings Part 5A). Owner/administrator only, same convention as Taxes: no
// separate view/edit split, since the whole destination is hidden from every other role.
export type InvoicePaymentTerm = {
	id: string;
	name: string;
	rule: 'on_receipt' | 'net_days' | 'month_end' | 'next_month_end';
	net_days: number | null;
	/** Built in: its name may be edited, but not its rule, and it cannot be removed. */
	is_protected: boolean;
};

export type InvoiceDefaults = {
	residential_term_id: string | null;
	commercial_term_id: string | null;
	revision: number;
	last_editor: SettingsEditor;
};

export type SettingsInvoices = {
	terms: InvoicePaymentTerm[];
	defaults: InvoiceDefaults;
};

export const settingsInvoicesKey = ['settings', 'invoices'] as const;

export async function fetchSettingsInvoices(): Promise<SettingsInvoices> {
	const response = await fetch('/api/settings/invoices');
	if (!response.ok) {
		const error = new Error('Invoice settings could not be loaded.') as SettingsReadError;
		error.status = response.status;
		throw error;
	}
	return response.json();
}

// Mirrors taxRequest above: these commands refuse by throwing, carrying the same {reason, fieldErrors} shape.
export type InvoiceTermWriteError = Error & {
	fieldErrors?: Record<string, string>;
	reason?: string;
};

async function invoiceTermRequest<T>(
	url: string,
	method: string,
	body: unknown,
	fallback: string
): Promise<T> {
	const response = await fetch(url, {
		method,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	if (!response.ok) {
		const result = await response
			.json()
			.catch(
				() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
			);
		const error = new Error(result.error ?? fallback) as InvoiceTermWriteError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return response.json();
}

export type InvoicePaymentTermSaveBody = {
	expected_revision: number;
	name: string;
	rule: InvoicePaymentTerm['rule'];
	net_days: number | null;
};

export function createInvoicePaymentTerm(
	body: InvoicePaymentTermSaveBody
): Promise<{ term_id: string; invoice_settings_revision: number }> {
	return invoiceTermRequest(
		'/api/settings/invoices',
		'POST',
		body,
		'That payment term could not be saved.'
	);
}

export function updateInvoicePaymentTerm(
	id: string,
	body: InvoicePaymentTermSaveBody
): Promise<{ term_id: string; invoice_settings_revision: number }> {
	return invoiceTermRequest(
		`/api/settings/invoices/terms/${id}`,
		'PATCH',
		body,
		'That payment term could not be saved.'
	);
}

export function removeInvoicePaymentTerm(
	id: string,
	body: { expected_revision: number }
): Promise<{ term_id: string; invoice_settings_revision: number }> {
	return invoiceTermRequest(
		`/api/settings/invoices/terms/${id}`,
		'DELETE',
		body,
		'That payment term could not be removed.'
	);
}

export function setInvoiceDefaults(body: {
	expected_revision: number;
	residential_term_id: string;
	commercial_term_id: string;
}): Promise<{ invoice_settings_revision: number }> {
	return invoiceTermRequest(
		'/api/settings/invoices/defaults',
		'PATCH',
		body,
		'Those defaults could not be saved.'
	);
}

// Settings → Payments (online payments Part 2). Owner/administrator only. The Stripe status is the safe
// shape the server builds — it never carries a key or a webhook secret.
export type StripeCheckStatus =
	'ok' | 'key_rejected' | 'permission_missing' | 'account_unavailable' | 'webhook_missing';

export type StripeConnectionStatus =
	| { connected: false }
	| {
			connected: true;
			account_name: string | null;
			stripe_account_id: string;
			livemode: boolean;
			key_last4: string;
			connected_at: string;
			last_checked_at: string;
			last_check_status: StripeCheckStatus;
	  };

export type PaymentSettings = {
	online_invoice_payments_enabled: boolean;
	online_deposit_payments_enabled: boolean;
	online_tips_enabled: boolean;
	online_receipt_email_enabled: boolean;
	pay_by_app_venmo_username: string | null;
	pay_by_app_cash_app_cashtag: string | null;
	pay_by_app_paypal_me_username: string | null;
	pay_by_app_zelle_contact: string | null;
	pay_by_app_e_transfer_email: string | null;
	pay_by_app_bank_transfer_instructions: string | null;
	revision: number;
};

export type SettingsPayments = { stripe: StripeConnectionStatus; settings: PaymentSettings };

export const settingsPaymentsKey = ['settings', 'payments'] as const;

export async function fetchSettingsPayments(): Promise<SettingsPayments> {
	const response = await fetch('/api/settings/payments');
	if (!response.ok) {
		const error = new Error('Payment settings could not be loaded.') as SettingsReadError;
		error.status = response.status;
		throw error;
	}
	return response.json();
}

export type StripeConnectError = Error & { fieldErrors?: Record<string, string>; reason?: string };

async function stripeRequest(url: string, method: string, body?: unknown) {
	const response = await fetch(url, {
		method,
		headers: body === undefined ? undefined : { 'content-type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	const result = await response.json().catch(() => ({}));
	if (!response.ok) {
		const error = new Error(
			result.error ?? 'Stripe could not be updated. Please try again.'
		) as StripeConnectError;
		error.fieldErrors = result.field_errors ?? {};
		error.reason = result.reason;
		throw error;
	}
	return result as { stripe: StripeConnectionStatus };
}

export function connectStripe(apiKey: string) {
	return stripeRequest('/api/settings/payments/stripe', 'POST', { api_key: apiKey });
}

export function disconnectStripe() {
	return stripeRequest('/api/settings/payments/stripe', 'DELETE');
}

export function checkStripeConnection() {
	return stripeRequest('/api/settings/payments/stripe/check', 'POST');
}

export type PaymentSettingsSaveResult = { status: 'saved'; payment_settings_revision: number };

export function savePaymentSettings(
	body: Omit<PaymentSettings, 'revision'> & { expected_revision: number }
): Promise<PaymentSettingsSaveResult | SettingsSaveConflict> {
	return saveSection('/api/settings/payments', body);
}
