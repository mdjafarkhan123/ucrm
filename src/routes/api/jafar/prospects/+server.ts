import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { prospectListQuerySchema } from '$lib/server/validation/prospect.schema';

const summarySelect =
	'id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone, trade, city_country, time_zone, package_version_id, package_snapshot, possible_duplicate, submitted_at, updated_at, not_proceeding_at';

function escapeProspectSearch(value: string) {
	return value
		.replaceAll('\\', '\\\\')
		.replaceAll('%', '\\%')
		.replaceAll('_', '\\_')
		.replace(/[(),]/g, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

export const GET: RequestHandler = async (event) => {
	if (!getOwnerSession(event)) return ownerUnauthorized();

	const parsed = prospectListQuerySchema.safeParse({
		stage: event.url.searchParams.get('stage') ?? undefined,
		search: event.url.searchParams.get('search') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The prospect filter is invalid.' }, { status: 422 });

	try {
		let query = getOwnerSupabaseClient()
			.from('platform_onboarding_applications')
			.select(summarySelect)
			.order('submitted_at', { ascending: false })
			.limit(100);

		if (parsed.data.stage) query = query.eq('stage', parsed.data.stage);
		if (parsed.data.search) {
			const search = escapeProspectSearch(parsed.data.search);
			query = query.or(
				`business_name.ilike.%${search}%,main_contact_name.ilike.%${search}%,main_contact_email.ilike.%${search}%`
			);
		}

		const { data, error } = await query;
		if (error) throw error;
		return json({ prospects: data ?? [] });
	} catch (error) {
		console.error('Could not load owner prospects.', error);
		return json({ error: 'Prospects could not be loaded.' }, { status: 500 });
	}
};
