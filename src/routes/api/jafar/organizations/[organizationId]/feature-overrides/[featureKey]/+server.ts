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
	featureOverrideSchema,
	organizationIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

const featureKeyPattern = /^[a-z][a-z0-9_.-]{1,79}$/;

function isInvalidWindow(startsAt: string, expiresAt: string | null | undefined) {
	return expiresAt ? Date.parse(expiresAt) <= Date.parse(startsAt) : false;
}

export const PUT: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const featureKey = event.params.featureKey;
	if (!parsedOrganizationId.success || !featureKeyPattern.test(featureKey)) {
		return json({ error: 'The organization or feature identifier is invalid.' }, { status: 422 });
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = featureOverrideSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the feature override.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		await resolveOrganizationAccess(client, organizationId);
		const { data: feature, error: featureError } = await client
			.from('features')
			.select('feature_key')
			.eq('feature_key', featureKey)
			.maybeSingle();
		if (featureError) throw featureError;
		if (!feature) return json({ error: 'Feature was not found.' }, { status: 404 });

		const { data: before, error: beforeError } = await client
			.from('organization_feature_overrides')
			.select('feature_key, override_state, starts_at, expires_at, updated_at')
			.eq('organization_id', organizationId)
			.eq('feature_key', featureKey)
			.maybeSingle();
		if (beforeError) throw beforeError;

		let after = null;
		if (parsed.data.override_state === 'inherit') {
			const { error } = await client
				.from('organization_feature_overrides')
				.delete()
				.eq('organization_id', organizationId)
				.eq('feature_key', featureKey);
			if (error) throw error;
		} else {
			const startsAt = parsed.data.starts_at ?? new Date().toISOString();
			if (isInvalidWindow(startsAt, parsed.data.expires_at)) {
				return json({ error: 'Expiry must be later than the start time.' }, { status: 422 });
			}
			const { data, error } = await client
				.from('organization_feature_overrides')
				.upsert(
					{
						organization_id: organizationId,
						feature_key: featureKey,
						override_state: parsed.data.override_state,
						starts_at: startsAt,
						expires_at: parsed.data.expires_at ?? null
					},
					{ onConflict: 'organization_id,feature_key' }
				)
				.select('feature_key, override_state, starts_at, expires_at, updated_at')
				.single();
			if (error) throw error;
			after = data;
		}

		await recordOwnerAccessAudit(client, {
			organization_id: organizationId,
			email: session.email,
			event_type: after ? 'feature_override.updated' : 'feature_override.inherited',
			target_type: 'organization.feature_override',
			target_key: featureKey,
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
		console.error('Could not change organization feature override.', error);
		return json({ error: 'Feature override could not be changed.' }, { status: 500 });
	}
};

export const DELETE: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const featureKey = event.params.featureKey;
	if (!parsedOrganizationId.success || !featureKeyPattern.test(featureKey)) {
		return json({ error: 'The organization or feature identifier is invalid.' }, { status: 422 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		await resolveOrganizationAccess(client, organizationId);
		const { data: before, error: beforeError } = await client
			.from('organization_feature_overrides')
			.select('feature_key, override_state, starts_at, expires_at, updated_at')
			.eq('organization_id', organizationId)
			.eq('feature_key', featureKey)
			.maybeSingle();
		if (beforeError) throw beforeError;
		const { error } = await client
			.from('organization_feature_overrides')
			.delete()
			.eq('organization_id', organizationId)
			.eq('feature_key', featureKey);
		if (error) throw error;

		await recordOwnerAccessAudit(client, {
			organization_id: organizationId,
			email: session.email,
			event_type: 'feature_override.inherited',
			target_type: 'organization.feature_override',
			target_key: featureKey,
			before_state: before,
			after_state: null
		});

		return json({ access: await resolveOrganizationAccess(client, organizationId) });
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError) {
			return json({ error: error.message }, { status: 404 });
		}
		console.error('Could not remove organization feature override.', error);
		return json({ error: 'Feature override could not be removed.' }, { status: 500 });
	}
};
