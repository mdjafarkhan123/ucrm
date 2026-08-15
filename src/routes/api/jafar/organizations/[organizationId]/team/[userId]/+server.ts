import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, userIdSchema } from '$lib/server/validation/access.schema';
import { teamProfileCorrectionSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';
import { recordOperationOutcome } from '$lib/server/events/outbox';

export const PATCH: RequestHandler = async (event) => {
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

	const parsed = teamProfileCorrectionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the correction.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const client = getOwnerSupabaseClient();

	try {
		const [membershipResult, profileResult] = await Promise.all([
			client
				.from('organization_members')
				.select('user_id, role')
				.eq('organization_id', organizationId)
				.eq('user_id', userId)
				.maybeSingle(),
			client.from('profiles').select('full_name').eq('id', userId).maybeSingle()
		]);
		if (membershipResult.error) throw membershipResult.error;
		if (!membershipResult.data)
			return json({ error: 'Team member was not found in this organization.' }, { status: 404 });
		if (profileResult.error) throw profileResult.error;

		// A single member's admin-API lookup can fail (seen for some legacy-seeded accounts) --
		// degrade to an unknown current email rather than 500ing the whole correction.
		let emailLookupFailed = false;
		let currentEmail: string | null = null;
		try {
			const { data, error } = await client.auth.admin.getUserById(userId);
			if (error) throw error;
			currentEmail = data.user?.email?.toLowerCase() ?? null;
		} catch (error) {
			console.error(`Could not resolve auth email for team member ${userId}.`, error);
			emailLookupFailed = true;
		}

		const currentFullName = profileResult.data?.full_name ?? null;

		const nextFullName = parsed.data.full_name ?? null;
		const nameChanged = nextFullName !== null && nextFullName !== currentFullName;

		const nextEmail = parsed.data.email ?? null;
		if (nextEmail !== null && emailLookupFailed) {
			return json(
				{ error: 'Could not verify the current login email. Try again in a moment.' },
				{ status: 502 }
			);
		}
		const emailChanged = nextEmail !== null && nextEmail !== currentEmail;

		if (emailChanged && (membershipResult.data.role === 'owner' || membershipResult.data.role === 'admin')) {
			return json(
				{ error: 'An administrator email change uses the recovery action instead.' },
				{ status: 409 }
			);
		}

		if (!nameChanged && !emailChanged) {
			return json({ error: 'Nothing to correct -- the values already match.' }, { status: 422 });
		}

		const idempotencyKey = parsed.data.idempotency_key;
		const operationTarget = { targetKind: 'organization' as const, targetId: organizationId };

		if (emailChanged) {
			try {
				const { error } = await client.auth.admin.updateUserById(userId, {
					email: nextEmail as string,
					email_confirm: true
				});
				if (error) throw error;
				await recordOperationOutcome(client, {
					operationType: 'organization_member_profile_correction',
					idempotencyKey,
					target: operationTarget,
					success: true
				});
			} catch (error) {
				await recordOperationOutcome(client, {
					operationType: 'organization_member_profile_correction',
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
		}

		const { data: command, error: rpcError } = await client.rpc(
			'apply_organization_member_profile_correction',
			{
				target_organization_id: organizationId,
				target_user_id: userId,
				new_full_name: (nameChanged ? nextFullName : null) as string,
				email_changed: emailChanged,
				old_email: (emailChanged ? currentEmail : null) as string,
				new_email: (emailChanged ? nextEmail : null) as string,
				private_reason: parsed.data.reason,
				actor_owner_email: session.email
			}
		);
		if (rpcError) {
			if (['23503', '23505', '23514', '40001'].includes(rpcError.code ?? '')) {
				return json({ error: rpcError.message }, { status: 409 });
			}
			throw rpcError;
		}

		return json({
			command,
			member: {
				user_id: userId,
				role: membershipResult.data.role,
				full_name: nameChanged ? nextFullName : currentFullName,
				email: emailChanged ? nextEmail : currentEmail
			}
		});
	} catch (error) {
		console.error('Could not correct the team member profile.', error);
		return json({ error: 'The profile correction could not be saved.' }, { status: 500 });
	}
};
