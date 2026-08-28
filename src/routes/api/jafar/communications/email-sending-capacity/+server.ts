import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationEmailSendingCapacitySchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

async function loadOverview() {
	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_email_sending_capacity_overview'
	);
	if (error) throw error;
	return data;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		return json({ overview: await loadOverview() }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the email sending-capacity overview.', error);
		return json(
			{ error: 'The email sending-capacity overview could not be loaded.' },
			{ status: 500 }
		);
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationEmailSendingCapacitySchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the change details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const change = parsed.data;
		let data: unknown = null;
		let error: { code?: string; message: string } | null = null;
		if (change.kind === 'warmup') {
			({ data, error } = await client.rpc('set_communication_email_warmup_stage', {
				p_stage_key: change.stage_key,
				p_daily_ceiling: change.daily_ceiling,
				p_reason: change.reason,
				p_actor_email: session.email,
				p_confirm_platform_change: change.confirm_platform_change
			}));
		} else if (change.kind === 'short_term') {
			({ data, error } = await client.rpc('set_communication_email_short_term_rate', {
				p_window_minutes: change.window_minutes,
				p_max_recipients: change.max_recipients,
				p_reason: change.reason,
				p_actor_email: session.email,
				p_confirm_platform_change: change.confirm_platform_change
			}));
		} else {
			({ data, error } = await client.rpc('set_communication_email_provider_capacity', {
				// The command accepts null to turn the limit off; the generated arg type omits that.
				p_capacity: (change.capacity ?? null) as number,
				p_reserve_percent: change.reserve_percent,
				p_reason: change.reason,
				p_actor_email: session.email,
				p_confirm_platform_change: change.confirm_platform_change
			}));
		}
		if (error) {
			// The command refuses an unconfirmed change and an out-of-bounds value the same way: a
			// check violation carrying the sentence Jafar should read.
			if (['23503', '23505', '23514'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		return json(
			{ result: data, overview: await loadOverview() },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not change an email sending-capacity setting.', error);
		return json({ error: 'The sending-capacity setting could not be changed.' }, { status: 500 });
	}
};
