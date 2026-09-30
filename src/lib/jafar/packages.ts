// Package builder P6: what Jafar's Packages page and builder read and send, and the pure rules the builder
// shows (required capabilities, what changed between two drafts). The API is src/routes/api/jafar/packages.

export type AllowanceState = 'numeric' | 'unlimited' | 'not_included';

export type PackageSummary = {
	id: string;
	slug: string;
	visibility: 'public' | 'private';
	display_order: number;
	archived_at: string | null;
	created_at: string;
	draft: {
		edition_id: string;
		revision: number;
		name: string;
		monthly_price_usd_cents: number | null;
		yearly_price_usd_cents: number | null;
		updated_at: string;
	} | null;
	published: {
		edition_id: string;
		edition_number: number;
		name: string;
		monthly_price_usd_cents: number | null;
		yearly_price_usd_cents: number | null;
		published_at: string;
	} | null;
	organization_count: number;
};

export type IncludedService = { name: string; description: string };
export type EditionAllowance = { key: string; state: AllowanceState; value: number | null };

export type EditionTerms = {
	edition_id: string;
	status: 'draft' | 'published' | 'superseded';
	edition_number: number | null;
	revision: number;
	name: string;
	promise: string | null;
	highlights: string[];
	included_services: IncludedService[];
	exclusions: string | null;
	monthly_price_usd_cents: number | null;
	yearly_price_usd_cents: number | null;
	updated_at: string;
	updated_by_email: string | null;
	capabilities: string[];
	allowances: EditionAllowance[];
};

export type CapabilityReference = {
	key: string;
	label: string;
	description: string;
	kind: 'core' | 'extra' | 'planned';
	sellable: boolean;
	requires: string[];
};

export type AllowanceReference = {
	key: string;
	capability_key: string | null;
	label: string;
	unit: 'seats' | 'recipients' | 'widgets' | 'conversations' | 'recipes';
	resets_monthly: boolean;
};

export type PackageBuilder = {
	package: {
		id: string;
		slug: string;
		visibility: 'public' | 'private';
		archived_at: string | null;
		ever_published: boolean;
		organization_count: number;
		email_template_count: number;
	};
	draft: EditionTerms | null;
	published: EditionTerms | null;
	capabilities: CapabilityReference[];
	allowances: AllowanceReference[];
};

/** The whole draft as the builder edits it and the save command receives it. */
export type DraftForm = {
	slug: string;
	name: string;
	promise: string;
	highlights: string[];
	included_services: IncludedService[];
	exclusions: string;
	monthly_price_usd_cents: number | null;
	yearly_price_usd_cents: number | null;
	capabilities: string[];
	allowances: EditionAllowance[];
};

export type ApiError = { error?: string; field_errors?: Record<string, string> };

export class PackageApiError extends Error {
	constructor(
		message: string,
		readonly status: number,
		readonly body: ApiError & { reason?: string; draft?: EditionTerms }
	) {
		super(message);
	}
}

async function send<T>(url: string, method: string, body?: unknown): Promise<T> {
	const response = await fetch(url, {
		method,
		headers: body === undefined ? undefined : { 'content-type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	const result = (await response.json().catch(() => ({}))) as T & ApiError;
	if (!response.ok) {
		throw new PackageApiError(
			result.error ?? 'Something went wrong. Try again.',
			response.status,
			result
		);
	}
	return result;
}

export async function fetchPackages() {
	return (await send<{ packages: PackageSummary[] }>('/api/jafar/packages', 'GET')).packages;
}

export async function fetchPackageBuilder(packageId: string) {
	return (await send<{ builder: PackageBuilder }>(`/api/jafar/packages/${packageId}`, 'GET'))
		.builder;
}

export function createPackage(input: {
	slug: string;
	name: string;
	idempotency_key: string;
	copy_from_package_id: string | null;
}) {
	return send<{ result: { package_id: string } }>('/api/jafar/packages', 'POST', input);
}

export function openPackageDraft(packageId: string) {
	return send<{ result: { edition_id: string } }>(`/api/jafar/packages/${packageId}/draft`, 'POST');
}

export function savePackageDraft(
	packageId: string,
	input: { edition_id: string; revision: number; terms: DraftForm }
) {
	return send<{ draft: EditionTerms }>(`/api/jafar/packages/${packageId}/draft`, 'PATCH', input);
}

export function deletePackageDraft(
	packageId: string,
	input: { edition_id: string; revision: number }
) {
	return send<{ package_removed: boolean }>(
		`/api/jafar/packages/${packageId}/draft`,
		'DELETE',
		input
	);
}

export function isStaleDraft(error: unknown): error is PackageApiError {
	return error instanceof PackageApiError && error.status === 409 && error.body.reason === 'stale';
}

export function formatUsd(cents: number | null) {
	if (cents === null) return '—';
	return `$${(cents / 100).toLocaleString('en-US', {
		minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
		maximumFractionDigits: 2
	})}`;
}

/** The public web address a package name suggests: "Growth Plus!" → "growth-plus". */
export function slugify(name: string) {
	return name
		.toLowerCase()
		.normalize('NFKD')
		.replace(/[̀-ͯ]/g, '')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '')
		.slice(0, 60)
		.replace(/-+$/g, '');
}

export function formFromTerms(terms: EditionTerms, slug: string): DraftForm {
	return {
		slug,
		name: terms.name,
		promise: terms.promise ?? '',
		highlights: [...terms.highlights],
		included_services: terms.included_services.map((service) => ({
			name: service.name,
			description: service.description ?? ''
		})),
		exclusions: terms.exclusions ?? '',
		monthly_price_usd_cents: terms.monthly_price_usd_cents,
		yearly_price_usd_cents: terms.yearly_price_usd_cents,
		capabilities: [...terms.capabilities],
		allowances: terms.allowances.map((allowance) => ({ ...allowance }))
	};
}

/**
 * The capabilities a draft includes but whose required capabilities it leaves out, each with what is
 * missing — "Website chat needs Shared inbox". Publishing refuses these; the builder offers to add them.
 */
export function missingRequirements(selected: string[], capabilities: CapabilityReference[]) {
	const chosen = new Set(selected);
	return capabilities
		.filter((capability) => chosen.has(capability.key))
		.map((capability) => ({
			capability,
			missing: capability.requires
				.filter((key) => !chosen.has(key))
				.map((key) => capabilities.find((candidate) => candidate.key === key))
				.filter((candidate): candidate is CapabilityReference => candidate !== undefined)
		}))
		.filter((entry) => entry.missing.length > 0);
}

/** An allowance applies when it belongs to every package or to a capability the draft includes. */
export function allowanceApplies(allowance: AllowanceReference, selected: string[]) {
	return allowance.capability_key === null || selected.includes(allowance.capability_key);
}

export type DraftDifference = { field: string; label: string; mine: string; saved: string };

function describeAllowances(form: DraftForm, allowances: AllowanceReference[]) {
	return allowances
		.filter((reference) => allowanceApplies(reference, form.capabilities))
		.map((reference) => {
			const value = form.allowances.find((allowance) => allowance.key === reference.key);
			const amount =
				!value || value.state === 'not_included'
					? 'not included'
					: value.state === 'unlimited'
						? 'unlimited'
						: String(value.value ?? 0);
			return `${reference.label}: ${amount}`;
		})
		.join(', ');
}

/**
 * What differs between the draft Jafar is editing and the one another tab saved, field by field, in
 * words he can compare before choosing which to keep.
 */
export function draftDifferences(
	mine: DraftForm,
	saved: DraftForm,
	capabilities: CapabilityReference[],
	allowances: AllowanceReference[]
): DraftDifference[] {
	const capabilityNames = (form: DraftForm) =>
		capabilities
			.filter(
				(capability) => capability.kind !== 'core' && form.capabilities.includes(capability.key)
			)
			.map((capability) => capability.label)
			.join(', ') || 'None';
	const text = (value: string) => value.trim() || '—';
	const fields: [string, string, (form: DraftForm) => string][] = [
		['name', 'Name', (form) => text(form.name)],
		['slug', 'Web address', (form) => text(form.slug)],
		['promise', 'Promise', (form) => text(form.promise)],
		['monthly', 'Monthly price', (form) => formatUsd(form.monthly_price_usd_cents)],
		['yearly', 'Yearly price', (form) => formatUsd(form.yearly_price_usd_cents)],
		['highlights', 'Customer highlights', (form) => form.highlights.join(' · ') || '—'],
		[
			'services',
			'Included services',
			(form) => form.included_services.map((service) => service.name).join(' · ') || '—'
		],
		['capabilities', 'Extra capabilities', capabilityNames],
		['allowances', 'Allowances', (form) => describeAllowances(form, allowances)],
		['exclusions', 'Exclusions and prerequisites', (form) => text(form.exclusions)]
	];
	return fields
		.map(([field, label, describe]) => ({
			field,
			label,
			mine: describe(mine),
			saved: describe(saved)
		}))
		.filter((difference) => difference.mine !== difference.saved);
}
