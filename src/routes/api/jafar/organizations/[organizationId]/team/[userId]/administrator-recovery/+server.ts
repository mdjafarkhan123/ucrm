import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { consumeOwnerStepUp, getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, userIdSchema } from '$lib/server/validation/access.schema';
import {
	administratorEmailRecoverySchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { sendAdministratorEmailRecoveryNotices } from '$lib/server/jafar/team-notifications';

function stepUpRequired() {
	return json(
		{
			error: 'Confirm your password before recovering administrator access.',
			step_up_required: true
		},
		{ status: 403 }
	);
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedOrganizationId.success || !parsedUserId.success) {
		return json({ error: 'The organization or member identifier is invalid.' }, { status: 422 });
	}
	const organizationId = parsedOrganizationId.data;
	const userId = parsedUserId.data;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = administratorEmailRecoverySchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the recovery details.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	if (!consumeOwnerStepUp(event, session)) return stepUpRequired();

	const client = getOwnerSupabaseClient();

	try {
		const [organizationResult, membershipResult] = await Promise.all([
			client.from('organizations').select('id, name').eq('id', organizationId).maybeSingle(),
			client
				.from('organization_members')
				.select('user_id, role')
				.eq('organization_id', organizationId)
				.eq('user_id', userId)
				.maybeSingle()
		]);
		if (organizationResult.error) throw organizationResult.error;
		if (!organizationResult.data)
			return json({ error: 'Organization was not found.' }, { status: 404 });
		if (membershipResult.error) throw membershipResult.error;
		if (!membershipResult.data)
			return json({ error: 'Team member was not found in this organization.' }, { status: 404 });
		if (membershipResult.data.role !== 'owner' && membershipResult.data.role !== 'admin') {
			return json(
				{ error: 'Administrator recovery only applies to an owner or admin.' },
				{ status: 409 }
			);
		}

		// A single member's admin-API lookup can fail (seen for some legacy-seeded accounts) --
		// degrade to an unknown current email rather than 500ing the whole recovery. The recovery
		// itself must still be able to proceed, since the locked-out administrator may be exactly
		// this broken account.
		let currentEmail: string | null = null;
		try {
			const { data, error } = await client.auth.admin.getUserById(userId);
			if (error) throw error;
			currentEmail = data.user?.email?.toLowerCase() ?? null;
		} catch (error) {
			console.error(`Could not resolve auth email for team member ${userId}.`, error);
		}

		const newEmail = parsed.data.new_email;
		if (newEmail === currentEmail) {
			return json({ error: 'This is already the current email.' }, { status: 422 });
		}

		const { data: isAvailable, error: availabilityError } = await client.rpc(
			'owner_email_is_available',
			{ candidate_email: newEmail }
		);
		if (availabilityError) throw availabilityError;
		if (!isAvailable) {
			return json({ error: 'This email is already in use on the platform.' }, { status: 409 });
		}

		const idempotencyKey = parsed.data.idempotency_key;
		const operationTarget = { targetKind: 'organization' as const, targetId: organizationId };

		try {
			const { error } = await client.auth.admin.updateUserById(userId, {
				email: newEmail,
				email_confirm: true
			});
			if (error) throw error;
			await recordOperationOutcome(client, {
				operationType: 'organization_administrator_email_recovery',
				idempotencyKey,
				target: operationTarget,
				success: true
			});
		} catch (error) {
			await recordOperationOutcome(client, {
				operationType: 'organization_administrator_email_recovery',
				idempotencyKey,
				target: operationTarget,
				actorEmail: session.email,
				success: false,
				error
			});
			return json(
				{ error: 'The login email could not be updated. This has been queued for retry.' },
				{ status: 502 }
			);
		}

		const { data: command, error: rpcError } = await client.rpc(
			'apply_organization_administrator_email_recovery',
			{
				target_organization_id: organizationId,
				target_user_id: userId,
				old_email: currentEmail as string,
				new_email: newEmail,
				evidence_summary: parsed.data.evidence_summary,
				private_reason: parsed.data.reason,
				actor_owner_email: session.email
			}
		);
		if (rpcError) {
			if (['23503', '23505', '23514', 'P0409'].includes(rpcError.code ?? '')) {
				return json({ error: rpcError.message }, { status: 409 });
			}
			throw rpcError;
		}

		await sendAdministratorEmailRecoveryNotices(client, {
			organizationId,
			userId,
			oldEmail: currentEmail,
			newEmail,
			businessName: organizationResult.data.name
		});

		return json({
			command,
			member: { user_id: userId, role: membershipResult.data.role, email: newEmail }
		});
	} catch (error) {
		console.error('Could not recover administrator access.', error);
		return json({ error: 'Administrator recovery could not be completed.' }, { status: 500 });
	}
};
