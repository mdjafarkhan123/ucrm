import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	organizationClosureStartSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { sendClosureNotice } from '$lib/server/jafar/organization-closure-cron';

function stepUpRequired() {
	return json(
		{
			error: 'Confirm your password before closing this organization.',
			step_up_required: true
		},
		{ status: 403 }
	);
}

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

	const parsed = organizationClosureStartSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the closure details.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) return stepUpRequired();

	try {
		const client = getOwnerSupabaseClient();
		const organizationId = parsedOrganizationId.data;

		const { data: organization, error: organizationError } = await client
			.from('organizations')
			.select('id, name, lifecycle_status')
			.eq('id', organizationId)
			.maybeSingle();
		if (organizationError) throw organizationError;
		if (!organization) return json({ error: 'Organization was not found.' }, { status: 404 });

		if (parsed.data.typed_organization_name !== organization.name) {
			return json(
				{
					error: 'The typed organization name does not match.',
					field_errors: { typed_organization_name: 'Type the organization name exactly to confirm.' }
				},
				{ status: 422 }
			);
		}

		const { data: command, error } = await client.rpc('apply_organization_closure_start', {
			target_organization_id: organizationId,
			idempotency_key: parsed.data.idempotency_key,
			private_reason: parsed.data.reason,
			actor_owner_email: session.email
		});
		if (error) {
			if (['23503', '23505', '23514', 'P0409'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		const applied = command as { applied: boolean; closure_record_id?: string } | null;
		if (applied?.applied && applied.closure_record_id) {
			await sendClosureNotice(client, {
				closureRecordId: applied.closure_record_id,
				organizationId,
				noticeKind: 'closure_started',
				mergeValues: {}
			}).catch((noticeError) =>
				console.error('Could not send the closure-started notice.', noticeError)
			);
		}

		const { data: refreshedOrganization, error: refreshedOrganizationError } = await client
			.from('organizations')
			.select('id, name, lifecycle_status')
			.eq('id', organizationId)
			.maybeSingle();
		if (refreshedOrganizationError) throw refreshedOrganizationError;

		return json({ command, organization: refreshedOrganization });
	} catch (error) {
		console.error('Could not start organization closure.', error);
		return json({ error: 'Organization closure could not be started.' }, { status: 500 });
	}
};
