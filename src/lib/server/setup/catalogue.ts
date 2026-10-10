import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueForServices,
	type SetupCatalogue,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';

// The Setup version one organization started with, read fresh on every request. Publishing a newer version never
// changes it (it is pinned when the organization's Industry experience is confirmed), so a client mid-setup keeps
// the questions they began with. Null when the organization is not pinned to a version.
export async function readOrganizationSetupVersion(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<SetupCatalogue | null> {
	const { data, error } = await supabase.rpc('setup_organization_catalogue', {
		target_organization_id: organizationId
	});
	if (error || !data) {
		if (error) console.error('Could not read the organization setup version.', error);
		return null;
	}
	return buildSetupCatalogue(data as unknown as SetupCatalogueRow);
}

/** Setup versions by id, for lists that measure many organizations that may be on different versions. */
export type SetupCatalogueSet = Map<string, SetupCatalogue>;

function catalogueSetFrom(data: unknown): SetupCatalogueSet {
	return new Map(
		Object.entries((data ?? {}) as Record<string, SetupCatalogueRow>).map(([id, row]) => [
			id,
			buildSetupCatalogue(row)
		])
	);
}

/** Every version some organization is pinned to (Uplift's service-role client only). Null when unreadable. */
export async function readSetupCataloguesInUse(
	supabase: SupabaseClient<Database>
): Promise<SetupCatalogueSet | null> {
	const { data, error } = await supabase.rpc('setup_catalogues_in_use');
	if (error) {
		console.error('Could not read the setup versions in use.', error);
		return null;
	}
	return catalogueSetFrom(data);
}

/**
 * The version each of these organizations is pinned to (Uplift's service-role client only). An organization with
 * no version is left out. Null when unreadable.
 */
export async function readOrganizationSetupVersions(
	supabase: SupabaseClient<Database>,
	organizationIds: string[]
): Promise<Map<string, SetupCatalogue> | null> {
	const ids = [...new Set(organizationIds)];
	if (ids.length === 0) return new Map();
	const pins = await supabase
		.from('organization_setup_versions')
		.select('organization_id, setup_version_id')
		.in('organization_id', ids);
	if (pins.error) {
		console.error('Could not read the organization setup versions.', pins.error);
		return null;
	}
	const versionIds = [...new Set(pins.data.map((pin) => pin.setup_version_id))];
	if (versionIds.length === 0) return new Map();
	const { data, error } = await supabase.rpc('setup_catalogues_for_versions', {
		version_ids: versionIds
	});
	if (error) {
		console.error('Could not read the setup versions.', error);
		return null;
	}
	const set = catalogueSetFrom(data);
	return new Map(
		pins.data.flatMap((pin) => {
			const catalogue = set.get(pin.setup_version_id);
			return catalogue ? [[pin.organization_id, catalogue] as const] : [];
		})
	);
}

/** The services of the organization's current package, which decide the stages it is asked. */
export async function readSetupServiceKeys(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<Set<string> | null> {
	const { data, error } = await supabase.rpc('setup_organization_service_keys', {
		target_organization_id: organizationId
	});
	if (error) {
		console.error('Could not read the organization package services.', error);
		return null;
	}
	return new Set(data ?? []);
}

/**
 * The version an organization started with, as it sees it: only the stages its package includes. Setup reads and
 * saves use this, so a client can never see, answer or finish a stage outside their package.
 */
export async function readOrganizationSetupCatalogue(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<SetupCatalogue | null> {
	const [catalogue, serviceKeys] = await Promise.all([
		readOrganizationSetupVersion(supabase, organizationId),
		readSetupServiceKeys(supabase, organizationId)
	]);
	if (!catalogue || !serviceKeys) return null;
	return catalogueForServices(catalogue, serviceKeys);
}

/** Each stage's title by key in the version an organization started with, for things that name a stage — a support chat asked from one, say. */
export async function readSetupSectionTitles(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<Map<string, string>> {
	const catalogue = await readOrganizationSetupVersion(supabase, organizationId);
	return sectionTitles(catalogue);
}

export function sectionTitles(catalogue: SetupCatalogue | null | undefined): Map<string, string> {
	return new Map(catalogue?.sections.map((section) => [section.key, section.title]) ?? []);
}

/** A stage since removed from the task list still reads as setup rather than as nothing. */
export function setupSectionLabel(titles: Map<string, string>, key: string | null): string | null {
	if (!key) return null;
	return titles.get(key) ?? 'Setup';
}
