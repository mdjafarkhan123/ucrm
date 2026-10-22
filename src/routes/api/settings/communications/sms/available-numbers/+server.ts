import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';
import { toShopNumber } from '$lib/server/communications/sms-number-shop';
import {
	smsNumberSearchSchema,
	smsSettingsFieldErrors
} from '$lib/server/validation/communications-sms-settings.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Live numbers for step 2 of Add number. Only numbers that can text are ever offered; picture messages and calls
// are optional filters. Stock changes by the minute, so this is never cached.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const parsed = smsNumberSearchSchema.safeParse(
		Object.fromEntries(event.url.searchParams.entries())
	);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the search.', field_errors: smsSettingsFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	const { country, type, contains, mms, voice } = parsed.data;
	try {
		const numbers = await getSmsCountryCatalog().searchNumbers({
			countryCode: country,
			numberType: type,
			sms: true,
			...(mms ? { mms: true } : {}),
			...(voice ? { voice: true } : {}),
			...(contains ? { contains } : {}),
			limit: 20
		});
		return json(
			{ numbers: numbers.filter((n) => n.capabilities.sms).map(toShopNumber) },
			{ headers: noStore }
		);
	} catch (error) {
		console.error('Could not search for numbers.', error);
		return json(
			{ error: 'The phone company could not be reached.', code: 'provider_unavailable' },
			{ status: 503, headers: noStore }
		);
	}
};
