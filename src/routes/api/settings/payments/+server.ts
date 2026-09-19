import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { isStale, settingsWriteError, staleSettingsResponse } from '$lib/server/settings/errors';
import { paymentSettingsSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { getStripeConnectionStatus } from '$lib/server/payments/stripe-connection';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Settings → Payments: the Stripe connection's safe status plus the contractor's payment switches.
// The status never carries a key, a webhook secret, or a Stripe error message.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.payments.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let stripe;
	try {
		stripe = await getStripeConnectionStatus(organizationId);
	} catch {
		return databaseError();
	}

	const { data: settings, error } = await event.locals.supabase
		.from('organization_settings')
		.select(
			'online_invoice_payments_enabled, online_deposit_payments_enabled, online_tips_enabled, online_receipt_email_enabled, pay_by_app_venmo_username, pay_by_app_cash_app_cashtag, pay_by_app_paypal_me_username, pay_by_app_zelle_contact, pay_by_app_e_transfer_email, pay_by_app_bank_transfer_instructions, payment_settings_revision'
		)
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (error || !settings) return databaseError();

	return json(
		{
			stripe,
			settings: {
				online_invoice_payments_enabled: settings.online_invoice_payments_enabled,
				online_deposit_payments_enabled: settings.online_deposit_payments_enabled,
				online_tips_enabled: settings.online_tips_enabled,
				online_receipt_email_enabled: settings.online_receipt_email_enabled,
				pay_by_app_venmo_username: settings.pay_by_app_venmo_username,
				pay_by_app_cash_app_cashtag: settings.pay_by_app_cash_app_cashtag,
				pay_by_app_paypal_me_username: settings.pay_by_app_paypal_me_username,
				pay_by_app_zelle_contact: settings.pay_by_app_zelle_contact,
				pay_by_app_e_transfer_email: settings.pay_by_app_e_transfer_email,
				pay_by_app_bank_transfer_instructions: settings.pay_by_app_bank_transfer_instructions,
				revision: settings.payment_settings_revision
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.payments.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-payments:${organizationId}`,
			...SAVE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = paymentSettingsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('set_organization_payment_settings', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		new_invoice_payments: parsed.data.online_invoice_payments_enabled,
		new_deposit_payments: parsed.data.online_deposit_payments_enabled,
		new_tips: parsed.data.online_tips_enabled,
		new_receipt_email: parsed.data.online_receipt_email_enabled,
		new_venmo_username: parsed.data.pay_by_app_venmo_username,
		new_cash_app_cashtag: parsed.data.pay_by_app_cash_app_cashtag,
		new_paypal_me_username: parsed.data.pay_by_app_paypal_me_username,
		new_zelle_contact: parsed.data.pay_by_app_zelle_contact,
		new_e_transfer_email: parsed.data.pay_by_app_e_transfer_email,
		new_bank_transfer_instructions: parsed.data.pay_by_app_bank_transfer_instructions
	});

	if (error) return settingsWriteError(error);
	if (isStale(data)) return staleSettingsResponse(data);

	return json(data, { headers: NO_STORE_HEADERS });
};
