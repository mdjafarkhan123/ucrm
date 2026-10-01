import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import type { PublicPackage, ShownOffer } from '$lib/packages/public-package';

// Package builder P9: the published edition of every public, unarchived package, with the capability and
// allowance labels a visitor reads. Private, archived, and superseded editions never leave this module.

const EDITION_COLUMNS = `id, status, name, promise, highlights, included_services, exclusions,
	monthly_price_usd_cents, yearly_price_usd_cents,
	packages!inner(slug, visibility, archived_at, display_order),
	package_edition_capabilities(capability_key, package_capabilities(label, description, kind, sort_order)),
	package_edition_allowances(allowance_key, allowance_state, allowance_value,
		package_allowances(label, unit, resets_monthly, sort_order))`;

function strings(value: unknown) {
	return Array.isArray(value)
		? value.filter((item): item is string => typeof item === 'string')
		: [];
}

function services(value: unknown) {
	if (!Array.isArray(value)) return [];
	return value.flatMap((item) =>
		item && typeof item === 'object' && typeof (item as { name?: unknown }).name === 'string'
			? [
					{
						name: (item as { name: string }).name,
						description: String((item as { description?: unknown }).description ?? '')
					}
				]
			: []
	);
}

type EditionRow = {
	id: string;
	name: string;
	promise: string | null;
	highlights: unknown;
	included_services: unknown;
	exclusions: string | null;
	monthly_price_usd_cents: number | null;
	yearly_price_usd_cents: number | null;
	packages: { slug: string; display_order: number };
	package_edition_capabilities: {
		capability_key: string;
		package_capabilities: {
			label: string;
			description: string;
			kind: string;
			sort_order: number;
		} | null;
	}[];
	package_edition_allowances: {
		allowance_key: string;
		allowance_state: string;
		allowance_value: number | null;
		package_allowances: {
			label: string;
			unit: string;
			resets_monthly: boolean;
			sort_order: number;
		} | null;
	}[];
};

type OfferRow = ShownOffer & { edition_id: string; package_slug: string };

// One edition row becomes one PublicPackage, for the visitor pages and for Jafar's draft preview alike, so
// both are built by the same code.
function toPublicPackage(
	edition: EditionRow,
	offerFor: (interval: 'month' | 'year') => ShownOffer | null
): PublicPackage {
	return {
		edition_id: edition.id,
		slug: edition.packages.slug,
		name: edition.name,
		promise: edition.promise,
		highlights: strings(edition.highlights),
		included_services: services(edition.included_services),
		exclusions: edition.exclusions,
		monthly_price_usd_cents: edition.monthly_price_usd_cents,
		yearly_price_usd_cents: edition.yearly_price_usd_cents,
		capabilities: edition.package_edition_capabilities
			.filter((row) => row.package_capabilities)
			.sort((a, b) => a.package_capabilities!.sort_order - b.package_capabilities!.sort_order)
			.map((row) => ({
				key: row.capability_key,
				label: row.package_capabilities!.label,
				description: row.package_capabilities!.description,
				core: row.package_capabilities!.kind === 'core'
			})),
		allowances: edition.package_edition_allowances
			.filter((row) => row.allowance_state !== 'not_included' && row.package_allowances)
			.sort((a, b) => a.package_allowances!.sort_order - b.package_allowances!.sort_order)
			.map((row) => ({
				key: row.allowance_key,
				label: row.package_allowances!.label,
				state: row.allowance_state as 'numeric' | 'unlimited',
				value: row.allowance_value,
				unit: row.package_allowances!.unit,
				resets_monthly: row.package_allowances!.resets_monthly
			})),
		offers: { month: offerFor('month'), year: offerFor('year') }
	};
}

async function loadOffers(client: SupabaseClient<Database>) {
	const { data, error } = await client.rpc('public_package_offers');
	if (error) throw error;
	return (data ?? []) as unknown as OfferRow[];
}

export async function loadPublicPackages(
	client: SupabaseClient<Database>,
	slug?: string
): Promise<PublicPackage[]> {
	let query = client
		.from('package_editions')
		.select(EDITION_COLUMNS)
		.eq('status', 'published')
		.eq('packages.visibility', 'public')
		.is('packages.archived_at', null);
	if (slug) query = query.eq('packages.slug', slug);
	const [{ data, error }, offers] = await Promise.all([query, loadOffers(client)]);
	if (error) throw error;

	// P11b: the automatic offer each edition gives a new customer today, per billing.
	return data
		.sort((a, b) => a.packages.display_order - b.packages.display_order)
		.map((edition) =>
			toPublicPackage(
				edition,
				(interval) =>
					offers.find(
						(offer) => offer.edition_id === edition.id && offer.billing_interval === interval
					) ?? null
			)
		);
}

/**
 * The package as a customer would see it, for Jafar's preview: its saved draft, or its published edition
 * when there is no draft. Visibility and archiving do not hide it from him. Offers are the ones the package
 * gives new customers today, so a draft shows what customers would be offered when it goes live.
 */
export async function loadPackagePreview(
	client: SupabaseClient<Database>,
	packageId: string
): Promise<{ pkg: PublicPackage; isDraft: boolean } | null> {
	const [{ data, error }, offers] = await Promise.all([
		client
			.from('package_editions')
			.select(EDITION_COLUMNS)
			.eq('package_id', packageId)
			.in('status', ['draft', 'published']),
		loadOffers(client)
	]);
	if (error) throw error;
	const edition = data.find((row) => row.status === 'draft') ?? data[0];
	if (!edition) return null;
	return {
		isDraft: edition.status === 'draft',
		pkg: toPublicPackage(
			edition,
			(interval) =>
				offers.find(
					(offer) =>
						offer.package_slug === edition.packages.slug && offer.billing_interval === interval
				) ?? null
		)
	};
}

/** What a marketing-site link asked for, and why it could not be honored when it could not. */
export type LinkChoice = {
	edition_id: string | null;
	billing: 'month' | 'year' | null;
	problem: 'unavailable' | 'interval_not_offered' | null;
	asked_slug: string | null;
};

export function readLinkChoice(url: URL, packages: PublicPackage[]): LinkChoice {
	const askedSlug = url.searchParams.get('package')?.trim().toLowerCase() || null;
	const askedBilling = url.searchParams.get('billing');
	const billing = askedBilling === 'year' || askedBilling === 'month' ? askedBilling : null;
	if (!askedSlug) return { edition_id: null, billing, problem: null, asked_slug: null };

	const match = packages.find((pkg) => pkg.slug === askedSlug);
	if (!match) return { edition_id: null, billing, problem: 'unavailable', asked_slug: askedSlug };

	const priced =
		billing === null ||
		(billing === 'month' ? match.monthly_price_usd_cents : match.yearly_price_usd_cents) !== null;
	return {
		edition_id: match.edition_id,
		billing,
		problem: priced ? null : 'interval_not_offered',
		asked_slug: askedSlug
	};
}
