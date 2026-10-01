import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { renderTemplate, htmlToPlainText } from '$lib/server/jafar/message-templates';
import { formatUsd } from '$lib/jafar/packages';
import { offerLength, type ShownOffer } from '$lib/packages/public-package';

type ApplicationSnapshot = {
	display_name?: string;
	price_usd_cents?: number;
	billing_period?: string;
	offer?: ShownOffer | null;
};

/**
 * The {{price}} an applicant sees on the received page and in the receipt: "$129/mo" or
 * "$1,290/yr, paid upfront", and with an introductory offer (package builder P11b) what they pay first:
 * "$64.50/mo for 3 months, then $129/mo".
 */
export function applicationPriceText(snapshot: ApplicationSnapshot) {
	if (typeof snapshot.price_usd_cents !== 'number') return '';
	const yearly = snapshot.billing_period === 'year';
	const per = yearly ? '/yr' : '/mo';
	const upfront = yearly ? ', paid upfront' : '';
	const offer = snapshot.offer;
	if (offer && typeof offer.intro_price_usd_cents === 'number') {
		return `${formatUsd(offer.intro_price_usd_cents)}${per} ${offerLength(offer.billing_interval, offer.periods)}, then ${formatUsd(offer.normal_price_usd_cents)}${per}${upfront}`;
	}
	return `${formatUsd(snapshot.price_usd_cents)}${per}${upfront}`;
}

type SendApplicationReceiptParams = {
	applicationId: string;
	recipientEmail: string;
	paymentInstructions: string;
	/** The applicant's own status page, so they can check progress without asking (behavior contract §1). */
	statusUrl: string;
};

/**
 * Reads the same immutable package_snapshot the /get-started/received page renders from, so the
 * price/package name a submitter sees never drifts even if a package's live price changes
 * moments later. Queued through the durable outbox (enqueueEmailDelivery) rather than sent
 * directly, so a Brevo outage surfaces as a retryable Operations row instead of a lost email.
 */
export async function sendApplicationReceipt(
	client: SupabaseClient<Database>,
	params: SendApplicationReceiptParams
) {
	const [applicationResult, templateResult] = await Promise.all([
		client
			.from('platform_onboarding_applications')
			.select('package_snapshot')
			.eq('id', params.applicationId)
			.single(),
		client
			.from('platform_message_templates')
			.select('subject_published, body_published')
			.eq('template_key', 'application_receipt')
			.maybeSingle()
	]);
	if (applicationResult.error) throw applicationResult.error;
	if (templateResult.error) throw templateResult.error;
	if (!templateResult.data?.body_published) {
		throw new Error('The application receipt template has not been published yet.');
	}

	const snapshot = applicationResult.data.package_snapshot as ApplicationSnapshot;
	const values = {
		package_name: snapshot.display_name ?? '',
		price: applicationPriceText(snapshot),
		payment_instructions: params.paymentInstructions
	};
	const subject = renderTemplate(templateResult.data.subject_published ?? '', values);
	// The status link is added after Jafar's wording rather than left to the template, so editing the
	// template can never drop the only way back to the status page.
	const templateBody = renderTemplate(templateResult.data.body_published, values);
	const body = `${templateBody}<p><a href="${encodeURI(params.statusUrl)}">Check where your application stands</a></p>`;
	const textBody = `${htmlToPlainText(templateBody)}\n\nCheck where your application stands: ${params.statusUrl}`;

	await enqueueEmailDelivery(client, {
		templateKey: 'application_receipt',
		target: { targetKind: 'onboarding_application', targetId: params.applicationId },
		idempotencyKey: `application:${params.applicationId}:receipt`,
		recipientEmail: params.recipientEmail,
		subject,
		htmlContent: body,
		textContent: textBody
	});
}
