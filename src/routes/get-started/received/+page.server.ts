import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { renderTemplate } from '$lib/server/jafar/message-templates';
import { applicationPriceText } from '$lib/server/jafar/application-receipt';
import type { PageServerLoad } from './$types';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Where the application stands, in the buyer's terms. Payment is only ever "confirmed" once Jafar has
 * verified the funds arrived (behavior contract §1), so a buyer who has paid but is not yet verified still
 * sees "waiting for payment" with a note that the check is under way.
 */
export type ApplicationStatus =
	'reviewing' | 'awaiting_payment' | 'setting_up' | 'account_ready' | 'payment_problem' | 'closed';

function statusFor(stage: string, paymentReversedAt: string | null): ApplicationStatus {
	if (stage === 'not_proceeding') return 'closed';
	if (paymentReversedAt) return 'payment_problem';
	switch (stage) {
		case 'new':
			return 'reviewing';
		case 'awaiting_payment':
			return 'awaiting_payment';
		// needs_attention without a reversal is a failed account set-up Jafar is fixing; the buyer's
		// money is confirmed, so to them the account is still being set up.
		case 'payment_confirmed':
		case 'needs_attention':
			return 'setting_up';
		case 'account_created':
			return 'account_ready';
		default:
			return 'closed';
	}
}

/**
 * The application id in the link is a random, unguessable id (same trust model as the
 * password-setup token) rather than a login -- looking it up here only reveals the price,
 * package, and progress of the applicant's own application, never anything about other applications.
 */
export const load: PageServerLoad = async ({ url }) => {
	const applicationId = url.searchParams.get('app');
	if (!applicationId || !UUID_PATTERN.test(applicationId)) {
		return { status: null, renderedBody: null };
	}

	const client = getOwnerSupabaseClient();

	const [applicationResult, settings, templateResult] = await Promise.all([
		client
			.from('platform_onboarding_applications')
			.select('package_snapshot, stage, payment_reversed_at')
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

	const application = applicationResult.data;
	if (!application) return { status: null, renderedBody: null };

	const status = statusFor(application.stage, application.payment_reversed_at);
	// The price and payment instructions only help while payment is still to be made.
	const snapshot = application.package_snapshot as
		Parameters<typeof applicationPriceText>[0] | null;
	if (
		(status !== 'reviewing' && status !== 'awaiting_payment') ||
		!snapshot ||
		!templateResult.data?.body_published
	) {
		return { status, renderedBody: null };
	}

	const renderedBody = renderTemplate(templateResult.data.body_published, {
		package_name: snapshot.display_name ?? '',
		price: applicationPriceText(snapshot),
		payment_instructions: settings.payment_instructions ?? ''
	});

	return { status, renderedBody };
};
