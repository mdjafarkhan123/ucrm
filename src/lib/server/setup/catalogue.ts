import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
	catalogueForServices,
	type SetupCatalogue,
	type SetupCatalogueRow
} from '$lib/setup/catalogue';

// The published setup version, read fresh on every request so a client mid-setup sees Jafar's published
// change at once (plan §2.1). One small indexed read: the version's stages and items.
export async function readSetupCatalogue(
	supabase: SupabaseClient<Database>
): Promise<SetupCatalogue | null> {
	const { data, error } = await supabase.rpc('setup_published_catalogue');
	if (error || !data) {
		if (error) console.error('Could not read the published setup version.', error);
		return null;
	}
	return buildSetupCatalogue(data as unknown as SetupCatalogueRow);
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
 * The published version as one organization sees it: only the stages its package includes. Setup reads and
 * saves use this, so a client can never see, answer or finish a stage outside their package.
 */
export async function readOrganizationSetupCatalogue(
	supabase: SupabaseClient<Database>,
	organizationId: string
): Promise<SetupCatalogue | null> {
	const [catalogue, serviceKeys] = await Promise.all([
		readSetupCatalogue(supabase),
		readSetupServiceKeys(supabase, organizationId)
	]);
	if (!catalogue || !serviceKeys) return null;
	return catalogueForServices(catalogue, serviceKeys);
}

/** Each stage's title by key, for things that name a stage — a support chat asked from one, say. */
export async function readSetupSectionTitles(
	supabase: SupabaseClient<Database>
): Promise<Map<string, string>> {
	const catalogue = await readSetupCatalogue(supabase);
	return new Map(catalogue?.sections.map((section) => [section.key, section.title]) ?? []);
}

/** A stage since removed from the task list still reads as setup rather than as nothing. */
export function setupSectionLabel(titles: Map<string, string>, key: string | null): string | null {
	if (!key) return null;
	return titles.get(key) ?? 'Setup';
}
