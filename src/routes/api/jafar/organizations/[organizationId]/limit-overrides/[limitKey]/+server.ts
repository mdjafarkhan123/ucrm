import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	OrganizationAccessNotFoundError,
	resolveOrganizationAccess
} from '$lib/server/access/effective';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	limitKeySchema,
	limitOverrideSchema,
	organizationIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

function isInvalidWindow(startsAt: string, expiresAt: string | null | undefined) {
	return expiresAt ? Date.parse(expiresAt) <= Date.parse(startsAt) : false;
}

export const PUT: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedLimitKey = limitKeySchema.safeParse(event.params.limitKey);
	if (!parsedOrganizationId.success || !parsedLimitKey.success) {
		return json({ error: 'The organization or limit identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = limitOverrideSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the limit override.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const limitKey = parsedLimitKey.data;
		await resolveOrganizationAccess(client, organizationId);
		const { data: before, error: beforeError } = await client
			.from('organization_limit_overrides')
			.select('limit_key, limit_value, is_unlimited, starts_at, expires_at, updated_at')
			.eq('organization_id', organizationId)
			.eq('limit_key', limitKey)
			.maybeSingle();
		if (beforeError) throw beforeError;

		let after = null;
		if (parsed.data.override_state === 'inherit') {
			const { error } = await client
				.from('organization_limit_overrides')
				.delete()
				.eq('organization_id', organizationId)
				.eq('limit_key', limitKey);
			if (error) throw error;
		} else {
			const startsAt = parsed.data.starts_at ?? new Date().toISOString();
			if (isInvalidWindow(startsAt, parsed.data.expires_at)) {
				return json({ error: 'Expiry must be later than the start time.' }, { status: 422 });
			}
			const { data, error } = await client
				.from('organization_limit_overrides')
				.upsert(
					{
						organization_id: organizationId,
						limit_key: limitKey,
						limit_value: parsed.data.is_unlimited ? null : (parsed.data.limit_value ?? null),
						is_unlimited: parsed.data.is_unlimited,
						starts_at: startsAt,
						expires_at: parsed.data.expires_at ?? null
					},
					{ onConflict: 'organization_id,limit_key' }
				)
				.select('limit_key, limit_value, is_unlimited, starts_at, expires_at, updated_at')
				.single();
			if (error) throw error;
			after = data;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: organizationId,
			email: session.email,
			event_type: after ? 'limit_override.updated' : 'limit_override.inherited',
			target_type: 'organization.limit_override',
			target_key: limitKey,
			before_state: before,
			after_state: after
		});

		return json({
			override: after,
			access: await resolveOrganizationAccess(client, organizationId)
		});
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError) {
			return json({ error: error.message }, { status: 404 });
		}
		console.error('Could not change organization limit override.', error);
		return json({ error: 'Limit override could not be changed.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedLimitKey = limitKeySchema.safeParse(event.params.limitKey);
	if (!parsedOrganizationId.success || !parsedLimitKey.success) {
		return json({ error: 'The organization or limit identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const limitKey = parsedLimitKey.data;
		await resolveOrganizationAccess(client, organizationId);
		const { data: before, error: beforeError } = await client
			.from('organization_limit_overrides')
			.select('limit_key, limit_value, is_unlimited, starts_at, expires_at, updated_at')
			.eq('organization_id', organizationId)
			.eq('limit_key', limitKey)
			.maybeSingle();
		if (beforeError) throw beforeError;
		const { error } = await client
			.from('organization_limit_overrides')
			.delete()
			.eq('organization_id', organizationId)
			.eq('limit_key', limitKey);
		if (error) throw error;

		await recordOwnerAccessAudit(client, {
			organization_id: organizationId,
			email: session.email,
			event_type: 'limit_override.inherited',
			target_type: 'organization.limit_override',
			target_key: limitKey,
			before_state: before,
			after_state: null
		});

		return json({ access: await resolveOrganizationAccess(client, organizationId) });
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError) {
			return json({ error: error.message }, { status: 404 });
		}
		console.error('Could not remove organization limit override.', error);
		return json({ error: 'Limit override could not be removed.' }, { status: 500 });
	}
};
