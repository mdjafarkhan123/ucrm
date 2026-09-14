import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationSmsOrgModeSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { PLATFORM_OWNER_ACTOR_ID } from '$lib/server/communications/sms-owner';

// Stage 2C-6: read one organization's SMS mode inputs and the mode actually in effect, for the Jafar
// Integrations tab. Read-only; the mode itself is changed by POST below.
export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const [modeResult, effectiveModeResult] = await Promise.all([
			client
				.from('communication_sms_org_modes')
				.select('package_max_mode, chosen_mode, override_mode, override_reason, updated_at')
				.eq('organization_id', parsedOrganizationId.data)
				.maybeSingle(),
			client.rpc('communication_sms_effective_mode', {
				p_organization_id: parsedOrganizationId.data
			})
		]);
		if (modeResult.error) throw modeResult.error;
		if (effectiveModeResult.error) throw effectiveModeResult.error;

		return json(
			{ mode: modeResult.data ?? null, effective_mode: effectiveModeResult.data as string },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not load the SMS mode.', error);
		return json({ error: 'The SMS mode could not be loaded.' }, { status: 500 });
	}
};

// Stage 2C-5c: the platform owner sets one organization's SMS mode inputs -- the package ceiling, the
// contractor's chosen mode, or a reasoned override that takes precedence over both. A time-bound capability/
// limit exception is explicitly a routine action (docs/jafar-organization-management-mission.md "High-impact
// action security"), so no step-up is required here.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationSmsOrgModeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the mode change.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await client
			.from('communication_sms_org_modes')
			.select('package_max_mode, chosen_mode, override_mode, override_reason')
			.eq('organization_id', parsedOrganizationId.data)
			.maybeSingle();
		if (existingError) throw existingError;

		const result = await client.rpc('communication_sms_set_org_mode', {
			p_organization_id: parsedOrganizationId.data,
			p_set_by: PLATFORM_OWNER_ACTOR_ID,
			p_package_max_mode: parsed.data.package_max_mode,
			p_chosen_mode: parsed.data.chosen_mode,
			p_override_mode: parsed.data.override_mode,
			p_override_reason: parsed.data.override_reason,
			p_clear_override: parsed.data.clear_override
		});

		if (result.error) {
			if (['P0001', '23505', '23514'].includes(result.error.code ?? '')) {
				return json({ error: result.error.message }, { status: 409 });
			}
			throw result.error;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type: 'communication_sms_org_mode_set',
			target_type: 'communication_sms_org_mode',
			target_key: parsedOrganizationId.data,
			before_state: existing ?? null,
			after_state: result.data
		});

		return json({ mode: result.data }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not set the SMS mode.', error);
		return json({ error: 'The SMS mode could not be set.' }, { status: 500 });
	}
};
