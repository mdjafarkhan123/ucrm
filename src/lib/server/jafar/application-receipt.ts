import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { renderTemplate, htmlToPlainText } from '$lib/server/jafar/message-templates';

function formatPrice(cents: number) {
	return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 0 })}/mo`;
}

type SendApplicationReceiptParams = {
	applicationId: string;
	recipientEmail: string;
	paymentInstructions: string;
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

	const snapshot = applicationResult.data.package_snapshot as {
		display_name?: string;
		price_usd_cents?: number;
	};
	const values = {
		package_name: snapshot.display_name ?? '',
		price: typeof snapshot.price_usd_cents === 'number' ? formatPrice(snapshot.price_usd_cents) : '',
		payment_instructions: params.paymentInstructions
	};
	const subject = renderTemplate(templateResult.data.subject_published ?? '', values);
	const body = renderTemplate(templateResult.data.body_published, values);

	await enqueueEmailDelivery(client, {
		templateKey: 'application_receipt',
		target: { targetKind: 'onboarding_application', targetId: params.applicationId },
		idempotencyKey: `application:${params.applicationId}:receipt`,
		recipientEmail: params.recipientEmail,
		subject,
		htmlContent: body,
		textContent: htmlToPlainText(body)
	});
}
