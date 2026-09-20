import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{
				error: 'The organization identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedOrganizationId.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const [effectiveResult, overrideResult] = await Promise.all([
			client.rpc('effective_marketing_email_limit', { target_organization_id: organizationId }),
			client
				.from('organization_limit_overrides')
				.select('limit_state, limit_value, starts_at, expires_at, reason, actor_owner_email')
				.eq('organization_id', organizationId)
				.eq('limit_key', 'marketing_email_recipients')
				.maybeSingle()
		]);
		if (effectiveResult.error) throw effectiveResult.error;
		if (overrideResult.error) throw overrideResult.error;
		const effective = effectiveResult.data?.[0];
		if (!effective) throw new Error('The Marketing allowance could not be resolved.');
		return json(
			{ allowance: { effective, override: overrideResult.data } },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not load organization Marketing allowance.', error);
		return json({ error: 'The Marketing allowance could not be loaded.' }, { status: 500 });
	}
};
