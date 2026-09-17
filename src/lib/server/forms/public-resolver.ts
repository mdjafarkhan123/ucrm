import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import {
	isBookingOutcome,
	type BookableService,
	type FormContent,
	type FormOutcome
} from '$lib/forms/types';

export type ResolvedPublicForm = {
	organizationId: string;
	organizationSlug: string;
	// The business name a visitor sees in the SMS consent wording, and the country a local phone number belongs to.
	organizationName: string;
	countryCode: string | null;
	formId: string;
	outcome: FormOutcome;
	title: string;
	description: string | null;
	content: FormContent;
	services: BookableService[];
};

type VersionRow = { id: string; title: string; description: string | null; content: unknown };
type CatalogItemRow = {
	id: string;
	name: string;
	unit_price_minor: number;
	archived_at: string | null;
};

// The one place that decides whether an anonymous visitor may see this form at all. Mirrors the staff
// booking route's query shape minus the permission check, plus exactly what the database's own
// `get_public_form_available_slots`/`submit_form_response` require: org active, form not archived, enabled,
// and published. Any failure here must read as "not available" everywhere -- the /page and both
// /api/public/forms routes all call this so none of them can disagree with the database about it.
export async function resolvePublicForm(
	client: SupabaseClient<Database>,
	organizationSlug: string,
	formSlug: string
): Promise<ResolvedPublicForm | null> {
	const { data: organization, error: organizationError } = await client
		.from('organizations')
		.select('id, slug, name')
		.eq('slug', organizationSlug)
		.eq('lifecycle_status', 'active')
		.maybeSingle();
	if (organizationError || !organization) return null;

	const { data: settings, error: settingsError } = await client
		.from('organization_settings')
		.select('country_code')
		.eq('organization_id', organization.id)
		.maybeSingle();
	if (settingsError) return null;

	const { data: form, error: formError } = await client
		.from('forms')
		.select(
			'id, outcome, current_published_version_id, form_versions!form_versions_form_organization_fk(id, title, description, content)'
		)
		.eq('organization_id', organization.id)
		.eq('public_slug', formSlug)
		.is('archived_at', null)
		.eq('is_enabled', true)
		.not('current_published_version_id', 'is', null)
		.maybeSingle();
	if (formError || !form || !form.current_published_version_id) return null;

	const versions = form.form_versions as VersionRow[];
	const published = versions.find((v) => v.id === form.current_published_version_id);
	if (!published) return null;

	const outcome = form.outcome as FormOutcome;

	let services: BookableService[] = [];
	if (isBookingOutcome(outcome)) {
		const { data: bookableRows, error: bookableError } = await client
			.from('form_bookable_services')
			.select('catalog_item_id')
			.eq('form_id', form.id)
			.order('position');
		if (bookableError) return null;

		const catalogItemIds = (bookableRows ?? []).map((row) => row.catalog_item_id);
		const catalogItemsResult =
			catalogItemIds.length > 0
				? await client
						.from('catalog_items')
						.select('id, name, unit_price_minor, archived_at')
						.in('id', catalogItemIds)
						.is('archived_at', null)
				: { data: [] as CatalogItemRow[], error: null };
		if (catalogItemsResult.error) return null;

		const catalogItemsById = new Map(catalogItemsResult.data.map((item) => [item.id, item]));
		services = catalogItemIds
			.map((catalogItemId) => catalogItemsById.get(catalogItemId))
			.filter((item): item is CatalogItemRow => item !== undefined)
			.map((item) => ({
				catalog_item_id: item.id,
				name: item.name,
				unit_price_minor: item.unit_price_minor,
				archived_at: item.archived_at
			}));
	}

	return {
		organizationId: organization.id,
		organizationSlug: organization.slug,
		organizationName: organization.name,
		countryCode: settings?.country_code ?? null,
		formId: form.id,
		outcome,
		title: published.title,
		description: published.description,
		content: published.content as FormContent,
		services
	};
}
