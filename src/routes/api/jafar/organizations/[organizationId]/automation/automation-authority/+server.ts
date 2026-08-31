import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';
import {
	automationAuthoritySchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'cache-control': 'no-store' };

// One owner read: the two-axis authority state plus recent reasoned history, and the seven Automation
// limits (package default, effective value/source, and reasoned/effective-dated exception) in one payload.
async function loadAutomationAuthority(organizationId: string) {
	const client = getOwnerSupabaseClient();
	const [authorityResult, limitsResult] = await Promise.all([
		client.rpc('get_organization_automation_authority', { p_organization_id: organizationId }),
		client.rpc('get_organization_automation_limits', { p_organization_id: organizationId })
	]);
	if (authorityResult.error) throw authorityResult.error;
	if (limitsResult.error) throw limitsResult.error;
	return { authority: authorityResult.data, limits: limitsResult.data };
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		return json(await loadAutomationAuthority(organizationId.data), { headers: noStore });
	} catch (error) {
		console.error('Could not load Automation authority.', error);
		return json({ error: 'Automation authority could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success) {
		return json(
			{
				error: 'The organization identifier is invalid.',
				field_errors: zodAccessFieldErrors(organizationId.error)
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = automationAuthoritySchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the Automation authority change.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { error } = await client.rpc('set_organization_automation_authority', {
			p_organization_id: organizationId.data,
			p_axis: parsed.data.axis,
			p_engage: parsed.data.engage,
			p_reason: parsed.data.reason,
			p_actor_email: session.email,
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;

		return json(await loadAutomationAuthority(organizationId.data), { headers: noStore });
	} catch (error) {
		const code =
			typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : '';
		const message =
			typeof error === 'object' && error !== null && 'message' in error
				? String(error.message)
				: 'Automation authority could not be changed.';
		if (code === '23503') return json({ error: message }, { status: 404 });
		if (['23505', '23514', '40001'].includes(code))
			return json({ error: message }, { status: 409 });
		console.error('Could not change Automation authority.', error);
		return json({ error: 'Automation authority could not be changed.' }, { status: 500 });
	}
};
