import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import {
	OrganizationAccessNotFoundError,
	PACKAGE_ORDER,
	resolveOrganizationAccess,
	type PackageKey
} from '$lib/server/access/effective';
import { ownerUnauthorized, recordOwnerAccessAudit } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationIdSchema,
	packageChangeSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const PATCH: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

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

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = packageChangeSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the package change.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;
		const access = await resolveOrganizationAccess(client, organizationId);
		const targetKey = parsed.data.package_key as PackageKey;
		const currentKey = access.package.effective_key;
		const targetOrder = PACKAGE_ORDER[targetKey];
		const currentOrder = PACKAGE_ORDER[currentKey];
		const effectiveAt = parsed.data.effective_at ? new Date(parsed.data.effective_at) : null;

		if (targetOrder > currentOrder && effectiveAt) {
			return json({ error: 'Package upgrades take effect immediately.' }, { status: 422 });
		}
		if (targetOrder === currentOrder && effectiveAt) {
			return json({ error: 'The current package cannot be scheduled.' }, { status: 422 });
		}
		if (targetOrder < currentOrder && (!effectiveAt || effectiveAt.getTime() <= Date.now())) {
			return json(
				{ error: 'Package downgrades require a future effective date.' },
				{ status: 422 }
			);
		}

		const update =
			targetOrder < currentOrder
				? {
						package_key: currentKey,
						scheduled_package_key: targetKey,
						scheduled_package_effective_at: effectiveAt!.toISOString(),
						updated_at: new Date().toISOString()
					}
				: {
						package_key: targetKey,
						scheduled_package_key: null,
						scheduled_package_effective_at: null,
						updated_at: new Date().toISOString()
					};

		const { data, error } = await client
			.from('organizations')
			.update(update)
			.eq('id', organizationId)
			.select('id, package_key, scheduled_package_key, scheduled_package_effective_at, updated_at')
			.single();
		if (error) throw error;

		await recordOwnerAccessAudit(client, {
			organization_id: organizationId,
			email: session.email,
			event_type: 'package.updated',
			target_type: 'organization.package',
			before_state: {
				package_key: access.package.current_key,
				effective_package_key: access.package.effective_key,
				scheduled_package_key: access.package.scheduled_key,
				scheduled_package_effective_at: access.package.scheduled_effective_at
			},
			after_state: data
		});

		return json({
			organization: data,
			access: await resolveOrganizationAccess(client, organizationId)
		});
	} catch (error) {
		if (error instanceof OrganizationAccessNotFoundError) {
			return json({ error: error.message }, { status: 404 });
		}
		console.error('Could not change organization package.', error);
		return json({ error: 'Organization package could not be changed.' }, { status: 500 });
	}
};
