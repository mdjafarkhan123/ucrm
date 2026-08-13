import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { sendApplicationReceipt } from '$lib/server/jafar/application-receipt';
import {
	onboardingApplicationSubmissionSchema,
	zodOnboardingApplicationFieldErrors
} from '$lib/server/validation/get-started.schema';

// Postgres codes raised by submit_onboarding_application when the chosen package version is no
// longer published (check_violation) or no longer exists (foreign_key_violation).
const UNAVAILABLE_PACKAGE_CODES = new Set(['23514', '23503']);

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Please review the highlighted fields.' }, { status: 400 });
	}

	const parsed = onboardingApplicationSubmissionSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodOnboardingApplicationFieldErrors(parsed.error)
			},
			{ status: 422 }
		);

	const data = parsed.data;
	const client = getOwnerSupabaseClient();
	const clientAddress = event.getClientAddress();

	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `get_started_submit:${clientAddress}`,
			windowSeconds: 900,
			maxAttempts: 5
		});
		if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

		const turnstileOk = await verifyTurnstileToken(data.turnstile_token, clientAddress);
		if (!turnstileOk)
			return json({ error: "We couldn't verify you're human. Please try again." }, { status: 422 });

		const administratorName = data.is_administrator_same_as_contact
			? null
			: (data.initial_administrator_name ?? null);
		const administratorEmail = data.is_administrator_same_as_contact
			? null
			: (data.initial_administrator_email ?? null);

		const settings = await getOrCreateOwnerSettings(client);

		const { data: applicationId, error: submitError } = await client.rpc(
			'submit_onboarding_application',
			{
				target_business_name: data.business_name,
				target_main_contact_name: data.main_contact_name,
				target_main_contact_email: data.main_contact_email,
				target_main_contact_phone: data.main_contact_phone,
				target_initial_administrator_name: administratorName ?? '',
				target_initial_administrator_email: administratorEmail ?? '',
				target_trade: data.trade,
				target_city_country: data.city_country,
				target_time_zone: data.time_zone,
				target_note: data.note ?? '',
				target_package_version_id: data.package_version_id,
				target_privacy_policy_version: settings.privacy_policy_version,
				target_submitted_data: {
					business_name: data.business_name,
					main_contact_name: data.main_contact_name,
					main_contact_email: data.main_contact_email,
					main_contact_phone: data.main_contact_phone,
					is_administrator_same_as_contact: data.is_administrator_same_as_contact,
					initial_administrator_name: administratorName,
					initial_administrator_email: administratorEmail,
					trade: data.trade,
					city_country: data.city_country,
					time_zone: data.time_zone,
					note: data.note ?? null,
					package_version_id: data.package_version_id
				}
			}
		);
		// The package can be retired or removed between the visitor loading the page and submitting it.
		// The database refuses that on purpose, so it is the visitor's problem to fix, not a fault
		// worth waking the owner for: ask them to pick again instead of showing a server error.
		if (submitError && UNAVAILABLE_PACKAGE_CODES.has(submitError.code))
			return json(
				{
					error: 'That package is no longer available. Please choose another one.',
					field_errors: {
						package_version_id: 'That package is no longer available. Please choose another one.'
					}
				},
				{ status: 422 }
			);
		if (submitError) throw submitError;

		try {
			await raiseOwnerAlert(client, {
				kind: 'onboarding_application_submitted',
				severity: 'attention',
				title: `New application from ${data.business_name}`,
				body: `${data.main_contact_name} applied for ${data.trade} in ${data.city_country}.`,
				target: { targetKind: 'onboarding_application', targetId: applicationId },
				origin: event.url.origin
			});
		} catch (notificationError) {
			console.error('Could not record the new-application notification.', notificationError);
		}

		if (applicationId) {
			try {
				await sendApplicationReceipt(client, {
					applicationId,
					recipientEmail: data.main_contact_email,
					paymentInstructions: settings.payment_instructions ?? ''
				});
			} catch (receiptError) {
				console.error('Could not send the application receipt email.', receiptError);
			}
		}

		return json({ ok: true, applicationId });
	} catch (error) {
		console.error('Could not save the onboarding application.', error);
		try {
			await raiseOwnerAlert(client, {
				kind: 'onboarding_application_submission_failed',
				severity: 'urgent',
				title: `An application from ${data.business_name} failed to save`,
				body: error instanceof Error ? error.message.slice(0, 500) : String(error).slice(0, 500),
				target: { targetKind: 'platform', targetId: null },
				origin: event.url.origin
			});
		} catch (notificationError) {
			console.error('Could not record the submission-failure alert.', notificationError);
		}
		return json(
			{ error: 'We could not save your application. Please try again shortly.' },
			{ status: 500 }
		);
	}
};
