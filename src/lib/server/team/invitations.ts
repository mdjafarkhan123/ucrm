import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import { sendTransactionalEmail } from '$lib/server/email/brevo';

const INVITATION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const SAFE_DELIVERY_ERROR = 'The invitation email could not be delivered.';

export type TeamInvitationErrorCode =
	| 'seat_limit'
	| 'email_in_use'
	| 'invalid_adjustments'
	| 'invalid_or_expired'
	| 'acceptance_in_progress'
	| 'invitation_conflict'
	| 'service_unavailable';

export class TeamInvitationError extends Error {
	constructor(
		public readonly code: TeamInvitationErrorCode,
		message: string
	) {
		super(message);
		this.name = 'TeamInvitationError';
	}
}

export type InvitationPermissionAdjustment = {
	permission_key: string;
	override_state: 'grant' | 'deny';
	access_scope?: 'all';
};

type CreateInvitationParams = {
	organizationId: string;
	invitedBy: string;
	email: string;
	role: string;
	permissionAdjustments: InvitationPermissionAdjustment[];
	businessName: string;
	origin: string;
};

type InvitationRow = {
	id: string;
	invited_email: string;
};

type ManagedInvitationRow = InvitationRow & {
	invited_user_id: string | null;
	identity_cleanup_state: string;
	requested_permission_overrides: Json;
	role: string;
	state: string;
};

type ResendInvitationParams = {
	organizationId: string;
	invitationId: string;
	businessName: string;
	origin: string;
};

type CancelInvitationParams = {
	organizationId: string;
	invitationId: string;
	cancelledBy: string;
};

type ReplaceInvitationEmailParams = {
	organizationId: string;
	invitationId: string;
	replacedBy: string;
	email: string;
	businessName: string;
	origin: string;
};

type AcceptInvitationParams = {
	token: string;
	email: string;
	password: string;
};

type ClaimedInvitationRow = {
	claimed: boolean;
	invitation_id: string | null;
	invited_user_id: string | null;
};

type RpcResult<T> = Promise<{ data: T | null; error: RpcError | null }>;
type RpcError = { code?: string; message?: string; status?: number };
type InvitationRpc = (name: string, args: Record<string, unknown>) => RpcResult<unknown>;

function invitationRpc(client: SupabaseClient<Database>) {
	return client.rpc.bind(client) as unknown as InvitationRpc;
}

function hashInvitationToken(token: string) {
	return createHash('sha256').update(token).digest('hex');
}

function normalizeEmail(email: string) {
	return email.trim().toLowerCase();
}

function maskEmail(email: string) {
	const [local, domain] = email.split('@');
	if (!domain) return '';
	return `${local.slice(0, 1)}${'*'.repeat(Math.max(local.length - 1, 3))}@${domain}`;
}

function htmlEscape(value: string) {
	return value
		.replaceAll('&', '&amp;')
		.replaceAll('<', '&lt;')
		.replaceAll('>', '&gt;')
		.replaceAll('"', '&quot;')
		.replaceAll("'", '&#039;');
}

function invitationEmail(params: { businessName: string; origin: string; token: string }) {
	const link = new URL('/team-invitation', params.origin);
	link.searchParams.set('token', params.token);
	const businessName = htmlEscape(params.businessName);
	const subject = `You're invited to join ${params.businessName}`;
	const textContent = `You've been invited to join ${params.businessName} on UpliftContractor. Set up your account: ${link.toString()}`;
	const htmlContent = `<p>You've been invited to join <strong>${businessName}</strong> on UpliftContractor.</p><p><a href="${htmlEscape(link.toString())}">Set up your account</a></p><p>This link expires in seven days.</p>`;

	return { subject, textContent, htmlContent };
}

function isEmailInUseError(error: RpcError) {
	const message = error.message?.toLowerCase() ?? '';
	return (
		error.code === '23505' ||
		message.includes('already been registered') ||
		message.includes('already registered') ||
		message.includes('already exists') ||
		message.includes('duplicate key')
	);
}

function isOpenAcceptanceError(error: RpcError) {
	return error.message?.toLowerCase().includes('acceptance lease') ?? false;
}

export function mapTeamInvitationError(error: unknown): TeamInvitationError {
	if (error instanceof TeamInvitationError) return error;

	const candidate = (typeof error === 'object' && error !== null ? error : {}) as RpcError;
	const message = candidate.message?.toLowerCase() ?? '';

	if (isEmailInUseError(candidate)) {
		return new TeamInvitationError(
			'email_in_use',
			'That email cannot be invited. Ask the person to use another email.'
		);
	}
	if (message.includes('no employee seats are available')) {
		return new TeamInvitationError(
			'seat_limit',
			'Your team has no available seats. Increase the limit or remove a pending invitation.'
		);
	}
	if (isOpenAcceptanceError(candidate)) {
		return new TeamInvitationError(
			'acceptance_in_progress',
			'This invitation is being accepted right now. Try again shortly.'
		);
	}
	if (candidate.code === 'P0409' || message.includes('invitation')) {
		return new TeamInvitationError(
			'invitation_conflict',
			'The invitation changed while it was being processed. Try again.'
		);
	}
	if (candidate.code === '23514' || message.includes('permission adjustment')) {
		return new TeamInvitationError(
			'invalid_adjustments',
			'One or more permission adjustments are not available for that role.'
		);
	}
	return new TeamInvitationError(
		'service_unavailable',
		'The invitation could not be created right now. Try again.'
	);
}

async function findManagedInvitation(
	client: SupabaseClient<Database>,
	organizationId: string,
	invitationId: string
) {
	const { data, error } = await client
		.from('organization_member_invitations')
		.select(
			'id, invited_email, invited_user_id, identity_cleanup_state, requested_permission_overrides, role, state'
		)
		.eq('id', invitationId)
		.eq('organization_id', organizationId)
		.maybeSingle();

	if (error) throw mapTeamInvitationError(error);
	if (!data) {
		throw new TeamInvitationError('invalid_or_expired', 'That invitation is no longer available.');
	}
	return data as ManagedInvitationRow;
}

async function runRpc<T>(rpc: InvitationRpc, name: string, args: Record<string, unknown>) {
	const { data, error } = await rpc(name, args);
	if (error) throw mapTeamInvitationError(error);
	if (!data) throw mapTeamInvitationError(null);
	return data as T;
}

async function findInvitationByToken(client: SupabaseClient<Database>, token: string) {
	const { data, error } = await client
		.from('organization_member_invitations')
		.select(
			'id, invited_email, invited_user_id, expires_at, password_set_at, state, organizations(name)'
		)
		.eq('token_hash', hashInvitationToken(token))
		.maybeSingle();

	if (error)
		throw new TeamInvitationError('service_unavailable', 'The invitation could not be checked.');
	return data;
}

export async function inspectTeamInvitation(
	client: SupabaseClient<Database>,
	token: string
): Promise<{ valid: false } | { valid: true; emailHint: string; companyName: string }> {
	const invitation = await findInvitationByToken(client, token);
	const isUsable =
		invitation?.state === 'invited' &&
		Boolean(invitation.expires_at) &&
		new Date(invitation.expires_at!).getTime() > Date.now();

	if (!isUsable) return { valid: false };

	const organization = Array.isArray(invitation.organizations)
		? invitation.organizations[0]
		: invitation.organizations;
	return {
		valid: true,
		emailHint: maskEmail(invitation.invited_email),
		companyName: organization?.name ?? ''
	};
}

async function resumeOrExplainFailedClaim(
	client: SupabaseClient<Database>,
	token: string,
	email: string
): Promise<{ accepted: true }> {
	const invitation = await findInvitationByToken(client, token);
	if (!invitation || normalizeEmail(invitation.invited_email) !== normalizeEmail(email)) {
		throw new TeamInvitationError(
			'invalid_or_expired',
			'This invitation is invalid or has expired.'
		);
	}

	if (invitation.state === 'accepted') return { accepted: true };

	if (
		invitation.state === 'accepting' &&
		invitation.password_set_at &&
		invitation.invited_user_id
	) {
		const { data: authData, error: authError } = await client.auth.admin.getUserById(
			invitation.invited_user_id
		);
		const metadata = authData.user?.app_metadata;
		if (
			!authError &&
			authData.user &&
			metadata?.team_invitation_identity_for === invitation.id &&
			metadata.invitation_password_set_for === invitation.id
		) {
			const finalized = await runRpc<{ state: string }>(
				invitationRpc(client),
				'finalize_team_invitation',
				{ target_invitation_id: invitation.id }
			);
			if (finalized.state === 'accepted') return { accepted: true };
		}
	}

	if (
		invitation.state === 'accepting' &&
		invitation.expires_at &&
		new Date(invitation.expires_at).getTime() > Date.now()
	) {
		throw new TeamInvitationError(
			'acceptance_in_progress',
			'This invitation is being accepted right now. Try again shortly.'
		);
	}
	throw new TeamInvitationError('invalid_or_expired', 'This invitation is invalid or has expired.');
}

export async function acceptTeamInvitation(
	client: SupabaseClient<Database>,
	params: AcceptInvitationParams
) {
	const rpc = invitationRpc(client);
	const leaseNonce = randomUUID();
	const { data: claimData, error: claimError } = await rpc('claim_team_invitation', {
		target_token_hash: hashInvitationToken(params.token),
		target_email: normalizeEmail(params.email),
		target_lease_nonce: leaseNonce,
		target_lease_seconds: 900
	});
	if (claimError) throw mapTeamInvitationError(claimError);

	const claim = (claimData as ClaimedInvitationRow[] | null)?.[0];
	if (!claim?.claimed || !claim.invitation_id || !claim.invited_user_id) {
		return resumeOrExplainFailedClaim(client, params.token, params.email);
	}

	const invitationId = claim.invitation_id;
	const userId = claim.invited_user_id;
	const { data: authData, error: authReadError } = await client.auth.admin.getUserById(userId);
	if (authReadError || !authData.user) {
		throw new TeamInvitationError(
			'service_unavailable',
			'The invitation could not be completed right now. Try again shortly.'
		);
	}

	const appMetadata = authData.user.app_metadata ?? {};
	if (appMetadata.team_invitation_identity_for !== invitationId) {
		throw new TeamInvitationError(
			'service_unavailable',
			'The invitation could not be completed right now. Try again shortly.'
		);
	}

	if (appMetadata.invitation_password_set_for !== invitationId) {
		const { error: updateError } = await client.auth.admin.updateUserById(userId, {
			password: params.password,
			app_metadata: { ...appMetadata, invitation_password_set_for: invitationId }
		});
		if (updateError) {
			throw new TeamInvitationError(
				'service_unavailable',
				'The invitation could not be completed right now. Try again shortly.'
			);
		}
	}

	await runRpc(rpc, 'record_invitation_password_set', {
		target_invitation_id: invitationId,
		target_lease_nonce: leaseNonce
	});
	const finalized = await runRpc<{ state: string }>(rpc, 'finalize_team_invitation', {
		target_invitation_id: invitationId
	});
	if (finalized.state !== 'accepted') {
		throw new TeamInvitationError(
			'service_unavailable',
			'The invitation could not be completed right now. Try again shortly.'
		);
	}

	return { accepted: true as const };
}

export async function createTeamInvitation(
	client: SupabaseClient<Database>,
	params: CreateInvitationParams
) {
	const rpc = invitationRpc(client);
	const email = normalizeEmail(params.email);
	let invitation: InvitationRow;

	try {
		invitation = await runRpc<InvitationRow>(rpc, 'begin_team_invitation', {
			target_organization_id: params.organizationId,
			target_invited_email: email,
			target_role: params.role,
			target_invited_by: params.invitedBy,
			target_permission_overrides: params.permissionAdjustments as Json
		});
	} catch (error) {
		throw mapTeamInvitationError(error);
	}

	const attemptNonce = randomUUID();
	await runRpc(rpc, 'mark_team_invitation_auth_attempt_started', {
		target_invitation_id: invitation.id,
		target_attempt_nonce: attemptNonce
	});

	const { data: authData, error: authError } = await client.auth.admin.createUser({
		email,
		email_confirm: true,
		app_metadata: { team_invitation_identity_for: invitation.id }
	});
	if (authError || !authData.user) throw mapTeamInvitationError(authError);

	const token = randomBytes(32).toString('base64url');
	const expiresAt = new Date(Date.now() + INVITATION_TTL_MS).toISOString();
	await runRpc(rpc, 'attach_team_invitation_identity', {
		target_invitation_id: invitation.id,
		target_invited_user_id: authData.user.id,
		target_attempt_nonce: attemptNonce,
		target_token_hash: hashInvitationToken(token),
		target_expires_at: expiresAt
	});

	const message = invitationEmail({
		businessName: params.businessName,
		origin: params.origin,
		token
	});

	try {
		await sendTransactionalEmail({ to: { email }, ...message });
	} catch {
		await runRpc(rpc, 'record_team_invitation_delivery', {
			target_invitation_id: invitation.id,
			target_success: false,
			target_error: SAFE_DELIVERY_ERROR
		});
		return { invitationId: invitation.id, status: 'delivery_failed' as const };
	}

	await runRpc(rpc, 'record_team_invitation_delivery', {
		target_invitation_id: invitation.id,
		target_success: true,
		target_error: null
	});
	return { invitationId: invitation.id, status: 'sent' as const };
}

export async function resendTeamInvitation(
	client: SupabaseClient<Database>,
	params: ResendInvitationParams
) {
	const current = await findManagedInvitation(client, params.organizationId, params.invitationId);
	if (current.state !== 'invited') {
		throw new TeamInvitationError(
			current.state === 'accepting' ? 'acceptance_in_progress' : 'invalid_or_expired',
			current.state === 'accepting'
				? 'This invitation is being accepted right now. Try again shortly.'
				: 'That invitation is no longer available.'
		);
	}

	const token = randomBytes(32).toString('base64url');
	const expiresAt = new Date(Date.now() + INVITATION_TTL_MS).toISOString();
	const rpc = invitationRpc(client);
	const rotated = await runRpc<InvitationRow>(rpc, 'resend_team_invitation', {
		target_invitation_id: params.invitationId,
		target_token_hash: hashInvitationToken(token),
		target_expires_at: expiresAt
	});

	const message = invitationEmail({
		businessName: params.businessName,
		origin: params.origin,
		token
	});

	try {
		await sendTransactionalEmail({ to: { email: rotated.invited_email }, ...message });
	} catch {
		await runRpc(rpc, 'record_team_invitation_delivery', {
			target_invitation_id: params.invitationId,
			target_success: false,
			target_error: SAFE_DELIVERY_ERROR
		});
		return { invitationId: params.invitationId, status: 'delivery_failed' as const };
	}

	await runRpc(rpc, 'record_team_invitation_delivery', {
		target_invitation_id: params.invitationId,
		target_success: true,
		target_error: null
	});
	return { invitationId: params.invitationId, status: 'sent' as const };
}

export async function cancelTeamInvitation(
	client: SupabaseClient<Database>,
	params: CancelInvitationParams
) {
	const current = await findManagedInvitation(client, params.organizationId, params.invitationId);
	if (!['reserving', 'invited', 'accepting'].includes(current.state)) {
		throw new TeamInvitationError('invalid_or_expired', 'That invitation is no longer available.');
	}

	const rpc = invitationRpc(client);
	await runRpc(rpc, 'cancel_team_invitation', {
		target_invitation_id: params.invitationId,
		target_cancelled_by: params.cancelledBy
	});

	return { invitationId: params.invitationId, status: 'cancelled' as const };
}

async function releaseReplacementCleanupLease(
	rpc: InvitationRpc,
	invitationId: string,
	leaseNonce: string
) {
	try {
		await runRpc(rpc, 'release_team_invitation_reconciliation', {
			target_invitation_id: invitationId,
			target_lease_nonce: leaseNonce,
			target_safe_error: 'Invitation email replacement needs cleanup retry.'
		});
	} catch {
		// The bounded worker can recover an expired lease. Keep the caller-facing error stable.
	}
}

async function cleanupCancelledInvitationForReplacement(
	client: SupabaseClient<Database>,
	params: { organizationId: string; invitationId: string }
) {
	const rpc = invitationRpc(client);
	const leaseNonce = randomUUID();
	const claimed = await runRpc<ManagedInvitationRow>(
		rpc,
		'claim_cancelled_team_invitation_cleanup',
		{
			target_organization_id: params.organizationId,
			target_invitation_id: params.invitationId,
			target_lease_nonce: leaseNonce,
			target_lease_seconds: 300
		}
	);

	if (!claimed.invited_user_id) {
		await releaseReplacementCleanupLease(rpc, params.invitationId, leaseNonce);
		throw new TeamInvitationError(
			'service_unavailable',
			'The old invitation could not be cleaned up right now. Try again.'
		);
	}

	const { data: authData, error: authError } = await client.auth.admin.getUserById(
		claimed.invited_user_id
	);
	if (
		authError ||
		!authData.user ||
		authData.user.app_metadata?.team_invitation_identity_for !== params.invitationId
	) {
		await releaseReplacementCleanupLease(rpc, params.invitationId, leaseNonce);
		throw new TeamInvitationError(
			'service_unavailable',
			'The old invitation could not be cleaned up right now. Try again.'
		);
	}

	await runRpc(rpc, 'prepare_team_invitation_identity_cleanup', {
		target_invitation_id: params.invitationId,
		target_lease_nonce: leaseNonce
	});

	const { error: deleteError } = await client.auth.admin.deleteUser(claimed.invited_user_id);
	if (deleteError) {
		await releaseReplacementCleanupLease(rpc, params.invitationId, leaseNonce);
		throw new TeamInvitationError(
			'service_unavailable',
			'The old invitation could not be cleaned up right now. Try again.'
		);
	}

	await runRpc(rpc, 'settle_team_invitation_identity_cleanup', {
		target_invitation_id: params.invitationId,
		target_lease_nonce: leaseNonce
	});
}

export async function replaceTeamInvitationEmail(
	client: SupabaseClient<Database>,
	params: ReplaceInvitationEmailParams
) {
	let current = await findManagedInvitation(client, params.organizationId, params.invitationId);

	if (current.state === 'accepting') {
		throw new TeamInvitationError(
			'acceptance_in_progress',
			'This invitation is being accepted right now. Try again shortly.'
		);
	}

	if (['reserving', 'invited'].includes(current.state)) {
		await cancelTeamInvitation(client, {
			organizationId: params.organizationId,
			invitationId: params.invitationId,
			cancelledBy: params.replacedBy
		});
		current = await findManagedInvitation(client, params.organizationId, params.invitationId);
	}

	if (current.state !== 'cancelled') {
		throw new TeamInvitationError('invalid_or_expired', 'That invitation is no longer available.');
	}

	if (current.identity_cleanup_state === 'required') {
		await cleanupCancelledInvitationForReplacement(client, {
			organizationId: params.organizationId,
			invitationId: params.invitationId
		});
	} else if (current.identity_cleanup_state !== 'done') {
		throw new TeamInvitationError(
			'service_unavailable',
			'The old invitation could not be cleaned up right now. Try again.'
		);
	}

	return createTeamInvitation(client, {
		organizationId: params.organizationId,
		invitedBy: params.replacedBy,
		email: params.email,
		role: current.role,
		permissionAdjustments:
			current.requested_permission_overrides as InvitationPermissionAdjustment[],
		businessName: params.businessName,
		origin: params.origin
	});
}
