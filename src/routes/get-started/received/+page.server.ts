import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { renderTemplate } from '$lib/server/jafar/message-templates';
import type { PageServerLoad } from './$types';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function formatPrice(cents: number) {
	return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 0 })}/mo`;
}

/**
 * The application id in the link is a random, unguessable id (same trust model as the
 * password-setup token) rather than a login -- looking it up here only reveals the price
 * and package the applicant themselves already chose, never anything about other applications.
 */
export const load: PageServerLoad = async ({ url }) => {
	const applicationId = url.searchParams.get('app');
	if (!applicationId || !UUID_PATTERN.test(applicationId)) {
		return { renderedBody: null };
	}

	const client = getOwnerSupabaseClient();

	const [applicationResult, settings, templateResult] = await Promise.all([
		client
			.from('platform_onboarding_applications')
			.select('package_snapshot')
			.eq('id', applicationId)
			.maybeSingle(),
		getOrCreateOwnerSettings(client),
		client
			.from('platform_message_templates')
			.select('body_published')
			.eq('template_key', 'received_page')
			.maybeSingle()
	]);
	if (applicationResult.error) throw applicationResult.error;
	if (templateResult.error) throw templateResult.error;

	const snapshot = applicationResult.data?.package_snapshot as {
		display_name?: string;
		price_usd_cents?: number;
	} | null;
	if (!snapshot || !templateResult.data?.body_published) {
		return { renderedBody: null };
	}

	const renderedBody = renderTemplate(templateResult.data.body_published, {
		package_name: snapshot.display_name ?? '',
		price: typeof snapshot.price_usd_cents === 'number' ? formatPrice(snapshot.price_usd_cents) : '',
		payment_instructions: settings.payment_instructions ?? ''
	});

	return { renderedBody };
};
