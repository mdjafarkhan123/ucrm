import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationLifecycleSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

function unauthorized() {
	return json({ error: 'Platform owner authentication required.' }, { status: 401 });
}

function stepUpRequired() {
	return json(
		{ error: 'Confirm your password before changing organization status.', step_up_required: true },
		{ status: 403 }
	);
}

export const PATCH: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return unauthorized();

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

	const parsed = organizationLifecycleSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the requested status.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) return stepUpRequired();

	try {
		const supabase = getOwnerSupabaseClient();

		const { data: existing, error: existingError } = await supabase
			.from('organizations')
			.select('id, lifecycle_status')
			.eq('id', parsedOrganizationId.data)
			.maybeSingle();
		if (existingError) throw existingError;
		if (!existing) return json({ error: 'Organization was not found.' }, { status: 404 });

		if (parsed.data.status === 'active') {
			const { count, error: membershipError } = await supabase
				.from('organization_members')
				.select('*', { count: 'exact', head: true })
				.eq('organization_id', parsedOrganizationId.data)
				.eq('role', 'owner');
			if (membershipError) throw membershipError;
			if (!count)
				return json(
					{ error: 'Invite the first administrator before activation.' },
					{ status: 409 }
				);
		}

		const { data, error } = await supabase
			.from('organizations')
			.update({ lifecycle_status: parsed.data.status, updated_at: new Date().toISOString() })
			.eq('id', parsedOrganizationId.data)
			.select('id, lifecycle_status, updated_at')
			.single();
		if (error) {
			if (error.code === 'PGRST116')
				return json({ error: 'Organization was not found.' }, { status: 404 });
			throw error;
		}

		await recordOwnerAccessAudit(supabase, {
			organization_id: parsedOrganizationId.data,
			email: session.email,
			event_type: 'organization.lifecycle_changed',
			target_type: 'organization.lifecycle_status',
			before_state: { lifecycle_status: existing.lifecycle_status },
			after_state: { lifecycle_status: data.lifecycle_status }
		});

		return json({ organization: data });
	} catch (error) {
		console.error('Could not change organization lifecycle status.', error);
		return json({ error: 'Organization status could not be changed.' }, { status: 500 });
	}
};
