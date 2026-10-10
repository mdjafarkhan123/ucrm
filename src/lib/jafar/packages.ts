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
		/** Who this edition is sold to (multi-industry foundation B2). */
		experience_keys: string[];
	} | null;
	organization_count: number;
	/** Why a delete would be refused, in words for Jafar, or null when nobody ever used the package. */
	delete_blocker: string | null;
	website_update_pending_since: string | null;
	website_changes: Pick<CatalogEvent, 'event_type' | 'edition_number' | 'detail' | 'created_at'>[];
};

export type CatalogEventType =
	| 'created'
	| 'published'
	| 'visibility_changed'
	| 'moved'
	| 'archived'
	| 'restored'
	| 'draft_discarded'
	| 'website_confirmed';

export type CatalogEvent = {
	id: string;
	event_type: CatalogEventType;
	edition_number: number | null;
	detail: Record<string, unknown>;
	actor_email: string | null;
	created_at: string;
};

export type PublishProblem = { code: string; key: string | null; message: string };

export type IncludedService = { service_key: string; name: string; description: string };

/** One service on Jafar's list (client onboarding plan §2.1). Packages tick it; setup stages show by it. */
export type PackageService = {
	key: string;
	name: string;
	description: string;
	archived_at: string | null;
	package_count: number;
	/** The Industry experiences Uplift delivers it for (multi-industry foundation B2). */
	experience_keys: string[];
};
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
	experience_keys: string[];
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
	/** The capability family an experience must allow before a package sold to it can include this. */
	family: string;
};

/** An Industry experience Uplift sells packages to today: its newest published definition. */
export type ExperienceReference = { key: string; name: string; capability_families: string[] };

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
		website_update_pending_since: string | null;
		ever_published: boolean;
		organization_count: number;
		email_template_count: number;
	};
	draft: (EditionTerms & { publish_problems: PublishProblem[] }) | null;
	published: EditionTerms | null;
	history: CatalogEvent[];
	capabilities: CapabilityReference[];
	allowances: AllowanceReference[];
	services: PackageService[];
	experiences: ExperienceReference[];
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
	experience_keys: string[];
	capabilities: string[];
	allowances: EditionAllowance[];
};

export type ApiError = { error?: string; field_errors?: Record<string, string> };

export class PackageApiError extends Error {
	constructor(
		message: string,
		readonly status: number,
		readonly body: ApiError & {
			reason?: string;
			draft?: EditionTerms;
			problems?: PublishProblem[];
		}
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

export function deletePackage(packageId: string) {
	return send<{ deleted: boolean }>(`/api/jafar/packages/${packageId}`, 'DELETE');
}

export function publishPackageDraft(
	packageId: string,
	input: { edition_id: string; revision: number }
) {
	return send<{ edition_number: number }>(
		`/api/jafar/packages/${packageId}/publish`,
		'POST',
		input
	);
}

export async function createPackageService(input: { name: string; description: string }) {
	return (await send<{ services: PackageService[] }>('/api/jafar/package-services', 'POST', input))
		.services;
}

export type PackageServiceChange =
	| { action: 'update'; key: string; name: string; description: string }
	| { action: 'archive'; key: string }
	| { action: 'restore'; key: string };

export async function changePackageService(command: PackageServiceChange) {
	return (
		await send<{ services: PackageService[] }>('/api/jafar/package-services', 'PATCH', command)
	).services;
}

export type CatalogAction =
	| { action: 'set_visibility'; visibility: 'public' | 'private' }
	| { action: 'move'; direction: 'up' | 'down' }
	| { action: 'archive' }
	| { action: 'restore' }
	| { action: 'confirm_website'; pending_since: string };

export function changePackage(packageId: string, command: CatalogAction) {
	return send<{ applied: boolean }>(`/api/jafar/packages/${packageId}`, 'PATCH', command);
}

/** One catalog history entry in words: "Published edition 2, replacing edition 1". */
export function describeCatalogEvent(
	event: Pick<CatalogEvent, 'event_type' | 'edition_number' | 'detail'>
) {
	switch (event.event_type) {
		case 'created':
			return event.detail.copied_from_package_id ? 'Created as a copy' : 'Created';
		case 'published':
			return typeof event.detail.replaces_edition_number === 'number'
				? `Published edition ${event.edition_number}, replacing edition ${event.detail.replaces_edition_number}`
				: `Published edition ${event.edition_number}`;
		case 'visibility_changed':
			return event.detail.to === 'public'
				? 'Made public: listed for new customers'
				: 'Made private: assigned by you only';
		case 'moved':
			return event.detail.direction === 'down' ? 'Moved down the list' : 'Moved up the list';
		case 'archived':
			return 'Archived: hidden from new customers';
		case 'restored':
			return 'Restored';
		case 'draft_discarded':
			return 'Discarded a draft';
		case 'website_confirmed':
			return 'Confirmed the marketing site is up to date';
	}
}

/** Whether new customers can choose this package: public, published, and not archived. */
export function isListed(pkg: {
	visibility: 'public' | 'private';
	archived_at: string | null;
	published: unknown;
}) {
	return pkg.visibility === 'public' && pkg.archived_at === null && pkg.published !== null;
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
			// Services written before the service list have no key; the builder asks Jafar to pick one.
			service_key: service.service_key ?? '',
			name: service.name,
			description: service.description ?? ''
		})),
		exclusions: terms.exclusions ?? '',
		monthly_price_usd_cents: terms.monthly_price_usd_cents,
		yearly_price_usd_cents: terms.yearly_price_usd_cents,
		experience_keys: [...terms.experience_keys].sort(),
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

/**
 * Multi-industry foundation B2: for each experience the draft is sold to, what in it does not fit there — a
 * capability from a family the experience does not allow, or a service Uplift does not deliver for it.
 * Publishing refuses these; the builder shows them as Jafar edits.
 */
export function experienceFitGaps(
	form: Pick<DraftForm, 'experience_keys' | 'capabilities' | 'included_services'>,
	reference: Pick<PackageBuilder, 'capabilities' | 'services' | 'experiences'>
) {
	return reference.experiences
		.filter((experience) => form.experience_keys.includes(experience.key))
		.map((experience) => ({
			experience,
			misfits: [
				...reference.capabilities
					.filter(
						(capability) =>
							form.capabilities.includes(capability.key) &&
							!experience.capability_families.includes(capability.family)
					)
					.map((capability) => capability.label),
				...form.included_services
					.map((included) =>
						reference.services.find((service) => service.key === included.service_key)
					)
					.filter(
						(service): service is PackageService =>
							service !== undefined && !service.experience_keys.includes(experience.key)
					)
					.map((service) => service.name)
			]
		}))
		.filter((gap) => gap.misfits.length > 0);
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

export type DraftLine = { field: string; label: string; value: string };

/** Every term of a draft in words, in the order the builder shows them. */
export function describeDraft(
	form: DraftForm,
	capabilities: CapabilityReference[],
	allowances: AllowanceReference[],
	experiences: ExperienceReference[] = []
): DraftLine[] {
	const text = (value: string) => value.trim() || '—';
	const extras =
		capabilities
			.filter(
				(capability) => capability.kind !== 'core' && form.capabilities.includes(capability.key)
			)
			.map((capability) => capability.label)
			.join(', ') || 'None';
	const soldTo =
		form.experience_keys
			.map((key) => experiences.find((experience) => experience.key === key)?.name ?? key)
			.join(', ') || 'Nobody yet';
	return [
		{ field: 'name', label: 'Name', value: text(form.name) },
		{ field: 'experiences', label: 'Sold to', value: soldTo },
		{ field: 'slug', label: 'Web address', value: text(form.slug) },
		{ field: 'promise', label: 'Promise', value: text(form.promise) },
		{ field: 'monthly', label: 'Monthly price', value: formatUsd(form.monthly_price_usd_cents) },
		{ field: 'yearly', label: 'Yearly price', value: formatUsd(form.yearly_price_usd_cents) },
		{
			field: 'highlights',
			label: 'Customer highlights',
			value: form.highlights.join(' · ') || '—'
		},
		{
			field: 'services',
			label: 'Included services',
			value: form.included_services.map((service) => service.name).join(' · ') || '—'
		},
		{ field: 'capabilities', label: 'Extra capabilities', value: extras },
		{ field: 'allowances', label: 'Allowances', value: describeAllowances(form, allowances) },
		{ field: 'exclusions', label: 'Exclusions and prerequisites', value: text(form.exclusions) }
	];
}

/**
 * What differs between the draft Jafar is editing and the one another tab saved, field by field, in
 * words he can compare before choosing which to keep.
 */
export function draftDifferences(
	mine: DraftForm,
	saved: DraftForm,
	capabilities: CapabilityReference[],
	allowances: AllowanceReference[],
	experiences: ExperienceReference[] = []
): DraftDifference[] {
	const savedLines = describeDraft(saved, capabilities, allowances, experiences);
	return describeDraft(mine, capabilities, allowances, experiences)
		.map((line, index) => ({
			field: line.field,
			label: line.label,
			mine: line.value,
			saved: savedLines[index].value
		}))
		.filter((difference) => difference.mine !== difference.saved);
}
