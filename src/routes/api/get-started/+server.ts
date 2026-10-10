import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { Database } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { sendApplicationReceipt } from '$lib/server/jafar/application-receipt';
import { isEditionSoldTo } from '$lib/server/packages/public-packages';
import {
	onboardingApplicationSubmissionSchema,
	zodOnboardingApplicationFieldErrors
} from '$lib/server/validation/get-started.schema';

type SubmitArgs = Database['public']['Functions']['submit_onboarding_application']['Args'];

// Postgres codes raised by submit_onboarding_application when the chosen package edition is no
// longer published (check_violation) or no longer exists (foreign_key_violation).
const UNAVAILABLE_PACKAGE_CODES = new Set(['23514', '23503']);

function unavailablePackage() {
	return json(
		{
			error: 'That package has changed or is no longer offered. Please review it again.',
			field_errors: {
				package_edition_id:
					'That package has changed or is no longer offered. Please review it again.'
			}
		},
		{ status: 422 }
	);
}

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

		// Multi-industry foundation B2–B3: only an edition sold to the buyer's proposed experience can be
		// chosen, even from a hand-made link. A business that fits no listed type chooses none.
		if (
			data.package_edition_id &&
			data.proposed_experience_key &&
			!(await isEditionSoldTo(client, data.package_edition_id, data.proposed_experience_key))
		)
			return unavailablePackage();

		const settings = await getOrCreateOwnerSettings(client);

		// The generated types mark every argument as text, but the proposal and package are null for a
		// business that fits no listed type; PostgREST needs each one sent, so null is sent rather than left out.
		const { data: applicationId, error: submitError } = await client.rpc(
			'submit_onboarding_application',
			{
				target_business_name: data.business_name,
				target_main_contact_name: data.main_contact_name,
				target_main_contact_email: data.main_contact_email,
				target_main_contact_phone: data.main_contact_phone,
				target_initial_administrator_name: administratorName ?? '',
				target_initial_administrator_email: administratorEmail ?? '',
				target_described_work: data.described_work,
				target_proposed_experience_key: data.proposed_other
					? null
					: (data.proposed_experience_key ?? null),
				target_proposed_business_type_key: data.proposed_other
					? null
					: (data.proposed_business_type_key ?? null),
				target_proposed_other: data.proposed_other ?? null,
				target_city_country: data.city_country,
				target_time_zone: data.time_zone,
				target_note: data.note ?? '',
				target_package_edition_id: data.proposed_other ? null : (data.package_edition_id ?? null),
				target_billing_interval: data.proposed_other ? null : (data.billing_interval ?? null),
				target_privacy_policy_version: settings.privacy_policy_version,
				target_submitted_data: {
					business_name: data.business_name,
					main_contact_name: data.main_contact_name,
					main_contact_email: data.main_contact_email,
					main_contact_phone: data.main_contact_phone,
					is_administrator_same_as_contact: data.is_administrator_same_as_contact,
					initial_administrator_name: administratorName,
					initial_administrator_email: administratorEmail,
					described_work: data.described_work,
					proposed_experience_key: data.proposed_other ? null : data.proposed_experience_key,
					proposed_business_type_key: data.proposed_other ? null : data.proposed_business_type_key,
					proposed_other: data.proposed_other ?? null,
					city_country: data.city_country,
					time_zone: data.time_zone,
					note: data.note ?? null,
					package_edition_id: data.proposed_other ? null : data.package_edition_id,
					billing_interval: data.proposed_other ? null : data.billing_interval
				}
			} as unknown as SubmitArgs
		);
		// The package can be revised, retired, or removed between the visitor loading the page and
		// submitting it. The database refuses that on purpose so nobody agrees to terms they were not
		// shown; it is not a fault worth waking the owner for. The page reloads the packages and asks
		// the visitor to review the current terms.
		if (submitError && UNAVAILABLE_PACKAGE_CODES.has(submitError.code)) return unavailablePackage();
		// The kind of business was withdrawn from the list while the visitor filled in the form.
		if (submitError?.code === '22023')
			return json(
				{
					error: 'Choose what kind of business you run.',
					field_errors: { business_type: 'Choose what kind of business you run.' }
				},
				{ status: 422 }
			);
		if (submitError) throw submitError;

		try {
			await raiseOwnerAlert(client, {
				kind: 'onboarding_application_submitted',
				severity: 'attention',
				title: `New application from ${data.business_name}`,
				body: data.proposed_other
					? `${data.main_contact_name} applied without a listed business type (${data.proposed_other === 'medspa' ? 'Medspa or clinic' : 'something else'}) in ${data.city_country}. Review what they do and recommend a package.`
					: `${data.main_contact_name} applied from ${data.city_country}: ${data.described_work.slice(0, 200)}`,
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
					paymentInstructions: settings.payment_instructions ?? '',
					statusUrl: `${event.url.origin}/get-started/received?app=${applicationId}`
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
