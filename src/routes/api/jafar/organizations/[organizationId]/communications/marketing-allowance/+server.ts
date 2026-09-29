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
			// The newest exception that has not ended yet, whether it has started or is still to come.
			client
				.from('organization_package_exceptions')
				.select(
					'limit_state:allowance_state, limit_value:allowance_value, starts_at, expires_at:ends_at, reason, actor_owner_email'
				)
				.eq('organization_id', organizationId)
				.eq('allowance_key', 'marketing_email_recipients')
				.gt('ends_at', new Date().toISOString())
				.order('starts_at', { ascending: false })
				.order('created_at', { ascending: false })
				.limit(1)
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
