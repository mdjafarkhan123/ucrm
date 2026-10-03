import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	buildSetupCatalogue,
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
