import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { issueSetupLink } from '$lib/server/jafar/setup-link';
import { dispatchOutboxDelivery } from '$lib/server/events/dispatcher';
import { operationIdSchema } from '$lib/server/validation/operation.schema';

const retryableStatuses = ['pending', 'retrying', 'acknowledged'];

export const POST: RequestHandler = async (event) => {
	const session = getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = operationIdSchema.safeParse(event.params.operationId);
	if (!parsedId.success)
		return json({ error: 'The operation identifier is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();

	try {
		const { data: attempt, error: attemptError } = await client
			.from('platform_operation_attempts')
			.select('operation_type, target_id, idempotency_key, status')
			.eq('id', parsedId.data)
			.maybeSingle();
		if (attemptError) throw attemptError;
		if (!attempt) return json({ error: 'Operation was not found.' }, { status: 404 });
		if (!retryableStatuses.includes(attempt.status))
			return json({ error: 'This operation is not open for retry.' }, { status: 409 });

		if (attempt.operation_type === 'outbox_email_delivery') {
			await dispatchOutboxDelivery(client, attempt.idempotency_key);
			return json({ ok: true });
		}

		if (attempt.operation_type === 'setup_email_delivery') {
			if (!attempt.target_id)
				return json({ error: 'No application is linked to this operation.' }, { status: 409 });

			const { data: application, error: applicationError } = await client
				.from('platform_onboarding_applications')
				.select('business_name, main_contact_email, initial_administrator_email')
				.eq('id', attempt.target_id)
				.maybeSingle();
			if (applicationError) throw applicationError;
			if (!application)
				return json({ error: 'The linked application was not found.' }, { status: 404 });

			const { data: provision, error: provisionError } = await client
				.from('platform_onboarding_application_provisions')
				.select('administrator_user_id')
				.eq('application_id', attempt.target_id)
				.maybeSingle();
			if (provisionError) throw provisionError;
			if (!provision?.administrator_user_id)
				return json(
					{ error: 'No administrator account was found for this application.' },
					{ status: 409 }
				);

			const administratorEmail = (
				application.initial_administrator_email ?? application.main_contact_email
			)
				.trim()
				.toLowerCase();

			const result = await issueSetupLink(client, {
				applicationId: attempt.target_id,
				administratorUserId: provision.administrator_user_id,
				intendedEmail: administratorEmail,
				businessName: application.business_name,
				origin: event.url.origin,
				actorEmail: session.email
			});

			if (!result.sent)
				return json(
					{ error: result.error ?? 'The setup email could not be sent.' },
					{ status: 502 }
				);
			return json({ ok: true });
		}

		return json(
			{ error: 'This operation type is retried from its own screen, not from Operations.' },
			{ status: 409 }
		);
	} catch (error) {
		console.error('Could not retry the operation.', error);
		return json({ error: 'The operation could not be retried.' }, { status: 500 });
	}
};
