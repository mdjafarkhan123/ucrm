import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

// Stage 2C-6: list one organization's SMS credit top-up requests and its current balance, for the Jafar
// Commercial access tab. The balance sits here (rather than its own route) because a top-up decision is
// exactly the moment the owner needs to see it. Individual requests are decided by the [requestId] route.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const [requestsResult, accountResult, promoBalanceResult, spendableBalanceResult] =
			await Promise.all([
				client
					.from('communication_sms_credit_topup_requests')
					.select(
						'id, requested_amount_minor, currency_code, offsite_reference, note, status, requested_at, decided_by, decided_at, decision_reason, settled_amount_minor'
					)
					.eq('organization_id', parsedOrganizationId.data)
					.order('requested_at', { ascending: false }),
				client
					.from('communication_sms_credit_accounts')
					.select('currency_code, settled_balance_minor, reserved_balance_minor, updated_at')
					.eq('organization_id', parsedOrganizationId.data)
					.maybeSingle(),
				client.rpc('communication_sms_promotional_balance', {
					p_organization_id: parsedOrganizationId.data
				}),
				client.rpc('communication_sms_spendable_balance', {
					p_organization_id: parsedOrganizationId.data
				})
			]);
		if (requestsResult.error) throw requestsResult.error;
		if (accountResult.error) throw accountResult.error;
		if (promoBalanceResult.error) throw promoBalanceResult.error;
		if (spendableBalanceResult.error) throw spendableBalanceResult.error;

		return json(
			{
				requests: requestsResult.data ?? [],
				balance: {
					currency_code: accountResult.data?.currency_code ?? 'USD',
					settled_balance_minor: accountResult.data?.settled_balance_minor ?? 0,
					reserved_balance_minor: accountResult.data?.reserved_balance_minor ?? 0,
					promotional_balance_minor: promoBalanceResult.data ?? 0,
					spendable_balance_minor: spendableBalanceResult.data ?? 0
				}
			},
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not load the SMS credit top-ups.', error);
		return json({ error: 'The SMS credit top-ups could not be loaded.' }, { status: 500 });
	}
};
