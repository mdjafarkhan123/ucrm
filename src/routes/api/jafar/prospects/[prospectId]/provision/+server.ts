import { randomUUID } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { issueSetupLink } from '$lib/server/jafar/setup-link';
import { recordOperationOutcome } from '$lib/server/events/outbox';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { prospectActivationSchema, prospectIdSchema } from '$lib/server/validation/prospect.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// Package builder P10: activation creates the organization, its owner, the package agreement, the first
// charge, the initial payment applied to it, and coverage for the dates Jafar reviewed, in one database
// step. The login account is created first and removed again if that step fails.

const provisionableStages = ['payment_confirmed', 'needs_attention'];

function provisioningIdempotencyKey(applicationId: string) {
	return `application:${applicationId}:provisioning`;
}

function slugify(name: string) {
	return (
		name
			.toLowerCase()
			.replace(/[^a-z0-9]+/g, '-')
			.replace(/^-+|-+$/g, '')
			.slice(0, 80) || 'organization'
	);
}

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedId = prospectIdSchema.safeParse(event.params.prospectId);
	if (!parsedId.success)
		return json({ error: 'The prospect identifier is invalid.' }, { status: 422 });

	const applicationId = parsedId.data;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}
	const parsedBody = prospectActivationSchema.safeParse(body);
	if (!parsedBody.success)
		return json(
			{
				error: 'Review the dates to cover before activating.',
				field_errors: zodOwnerFieldErrors(parsedBody.error)
			},
			{ status: 422 }
		);

	const client = getOwnerSupabaseClient();

	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `provision_retry:${session.email}`,
			windowSeconds: 300,
			maxAttempts: 10
		});
		if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

		const { data: application, error: applicationError } = await client
			.from('platform_onboarding_applications')
			.select(
				'stage, business_name, main_contact_name, main_contact_email, initial_administrator_name, initial_administrator_email'
			)
			.eq('id', applicationId)
			.maybeSingle();
		if (applicationError) throw applicationError;
		if (!application) return json({ error: 'Prospect was not found.' }, { status: 404 });

		// A cheap read-only peek first: an already-succeeded provision can always be replayed, even
		// if the application's stage has since moved on, so this must not be blocked by the stage
		// check below. This does not need to be race-safe (unlike the actual claim) -- worst case a
		// concurrent finish is missed here and caught a moment later by the atomic claim RPC itself.
		const { data: existingProvision, error: provisionLookupError } = await client
			.from('platform_onboarding_application_provisions')
			.select('status, organization_id')
			.eq('application_id', applicationId)
			.maybeSingle();
		if (provisionLookupError) throw provisionLookupError;
		if (existingProvision?.status === 'succeeded' && existingProvision.organization_id) {
			return json({ organization_id: existingProvision.organization_id });
		}

		if (!provisionableStages.includes(application.stage))
			return json({ error: 'This application is not ready for provisioning.' }, { status: 409 });

		// Refuse before creating a login account when something stops activation or the reviewed dates
		// are stale; the database step checks both again.
		const offerChoice = {
			offer_decision: parsedBody.data.offer_decision ?? undefined,
			offer_code: parsedBody.data.offer_code ?? undefined
		};
		const { data: preview, error: previewError } = await client.rpc(
			'owner_onboarding_activation_preview',
			{ target_application_id: applicationId, ...offerChoice }
		);
		if (previewError) throw previewError;
		const activation = preview as {
			problems: string[];
			covered_from: string;
			covered_through: string;
			first_charge_usd_cents: number | null;
		} | null;
		if (!activation) return json({ error: 'Prospect was not found.' }, { status: 404 });
		if (activation.problems.length > 0)
			return json({ error: activation.problems[0] }, { status: 409 });
		if (
			activation.covered_from !== parsedBody.data.covered_from ||
			activation.covered_through !== parsedBody.data.covered_through
		)
			return json(
				{
					error:
						'The dates to cover have changed since you reviewed them. Review them and try again.',
					reason: 'dates_changed'
				},
				{ status: 409 }
			);
		const expectedFirstCharge = parsedBody.data.expected_first_charge_usd_cents ?? null;
		if (expectedFirstCharge !== null && activation.first_charge_usd_cents !== expectedFirstCharge)
			return json(
				{
					error: 'The first charge has changed since you reviewed it. Review it and try again.',
					reason: 'dates_changed'
				},
				{ status: 409 }
			);

		const { data: claimRows, error: claimError } = await client.rpc(
			'claim_onboarding_application_provision',
			{ target_application_id: applicationId }
		);
		if (claimError) throw claimError;
		const claim = claimRows?.[0];
		if (!claim) throw new Error('The provisioning claim did not return a result.');

		if (claim.claim_status === 'already_succeeded' && claim.organization_id) {
			return json({ organization_id: claim.organization_id });
		}
		if (claim.claim_status === 'in_progress') {
			return json(
				{ error: 'This application is already being provisioned. Please wait and refresh.' },
				{ status: 409 }
			);
		}

		let administratorUserId = claim.administrator_user_id;

		const administratorEmail = (
			application.initial_administrator_email ?? application.main_contact_email
		)
			.trim()
			.toLowerCase();
		const administratorName =
			application.initial_administrator_name ?? application.main_contact_name;

		const organizationId = randomUUID();
		const baseSlug = slugify(application.business_name);
		const { data: existingSlugs, error: slugError } = await client
			.from('organizations')
			.select('slug')
			.ilike('slug', `${baseSlug}%`);
		if (slugError) throw slugError;
		const takenSlugs = new Set((existingSlugs ?? []).map((organization) => organization.slug));
		let slug = baseSlug;
		let suffix = 2;
		while (takenSlugs.has(slug)) slug = `${baseSlug}-${suffix++}`;

		if (!administratorUserId) {
			const { data: createdUser, error: createUserError } = await client.auth.admin.createUser({
				email: administratorEmail,
				email_confirm: true,
				user_metadata: { full_name: administratorName },
				app_metadata: { organization_id: organizationId, role: 'owner' }
			});
			if (createUserError || !createdUser.user) {
				const alreadyExists = createUserError?.message.toLowerCase().includes('already') ?? false;
				const failureReason = alreadyExists
					? 'An administrator already uses this email address.'
					: 'The administrator account could not be created.';
				await client
					.from('platform_onboarding_application_provisions')
					.update({ status: 'failed', last_error: failureReason })
					.eq('application_id', applicationId);
				await recordOperationOutcome(client, {
					operationType: 'onboarding_application_provisioning',
					idempotencyKey: provisioningIdempotencyKey(applicationId),
					target: { targetKind: 'onboarding_application', targetId: applicationId },
					actorEmail: session.email,
					success: false,
					error: failureReason
				});
				return json({ error: failureReason }, { status: alreadyExists ? 409 : 503 });
			}

			administratorUserId = createdUser.user.id;
			// Persist the login account id before the organization RPC runs, so a crash or restart
			// between here and a successful RPC leaves a trail: the next claim resumes with this id
			// instead of calling createUser again (which would fail, since the account already exists).
			const { error: recordAdminIdError } = await client
				.from('platform_onboarding_application_provisions')
				.update({ administrator_user_id: administratorUserId })
				.eq('application_id', applicationId);
			if (recordAdminIdError)
				console.error('Could not record the new administrator account id.', recordAdminIdError);
		}

		const { error: rpcError } = await client.rpc('provision_organization_from_application', {
			target_application_id: applicationId,
			target_organization_id: organizationId,
			target_organization_name: application.business_name,
			target_slug: slug,
			target_administrator_user_id: administratorUserId,
			target_actor_owner_email: session.email,
			expected_covered_from: parsedBody.data.covered_from,
			expected_covered_through: parsedBody.data.covered_through,
			...offerChoice,
			expected_first_charge_usd_cents: expectedFirstCharge ?? undefined
		});

		if (rpcError) {
			const { error: deleteUserError } = await client.auth.admin.deleteUser(administratorUserId);
			if (deleteUserError)
				console.error('Could not compensate the failed administrator account.', deleteUserError);
			await client
				.from('platform_onboarding_applications')
				.update({ stage: 'needs_attention' })
				.eq('id', applicationId);
			await client
				.from('platform_onboarding_application_provisions')
				.update({
					status: 'failed',
					last_error: rpcError.message,
					// Only clear the stored account id once it's actually deleted -- if deletion failed,
					// the account still exists, so a future retry must keep resuming with the same id
					// instead of trying to create a second one.
					administrator_user_id: deleteUserError ? administratorUserId : null
				})
				.eq('application_id', applicationId);
			await recordOperationOutcome(client, {
				operationType: 'onboarding_application_provisioning',
				idempotencyKey: provisioningIdempotencyKey(applicationId),
				target: { targetKind: 'onboarding_application', targetId: applicationId },
				actorEmail: session.email,
				success: false,
				error: rpcError.message
			});
			try {
				await raiseOwnerAlert(client, {
					kind: 'onboarding_application_provisioning_failed',
					severity: 'urgent',
					title: `Provisioning failed for ${application.business_name}`,
					body: `The application was moved to needs attention. ${rpcError.message}`.slice(0, 500),
					target: { targetKind: 'onboarding_application', targetId: applicationId },
					origin: event.url.origin
				});
			} catch (alertError) {
				console.error('Could not raise the provisioning-failure alert.', alertError);
			}
			console.error('Could not provision the organization.', rpcError);
			return json(
				{
					error:
						'The organization could not be provisioned. The application was moved to needs attention.'
				},
				{ status: 500 }
			);
		}

		const { error: succeededError } = await client
			.from('platform_onboarding_application_provisions')
			.update({
				status: 'succeeded',
				organization_id: organizationId,
				administrator_user_id: administratorUserId,
				last_error: null
			})
			.eq('application_id', applicationId);
		if (succeededError)
			console.error('Could not record the successful provisioning attempt.', succeededError);
		await recordOperationOutcome(client, {
			operationType: 'onboarding_application_provisioning',
			idempotencyKey: provisioningIdempotencyKey(applicationId),
			target: { targetKind: 'onboarding_application', targetId: applicationId },
			success: true
		});

		const setupLinkResult = await issueSetupLink(client, {
			applicationId,
			administratorUserId,
			intendedEmail: administratorEmail,
			businessName: application.business_name,
			origin: event.url.origin,
			actorEmail: session.email
		});

		return json(
			{ organization_id: organizationId, setup_email_sent: setupLinkResult.sent },
			{ status: 201 }
		);
	} catch (error) {
		console.error('Could not provision the organization.', error);
		return json({ error: 'The organization could not be provisioned.' }, { status: 500 });
	}
};
