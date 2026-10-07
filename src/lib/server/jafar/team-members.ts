import { createHash, randomBytes } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import bcrypt from 'bcryptjs';
import type { Database } from '$lib/database.types';
import { TEAM_ROLE_LABELS, type TeamRole } from '$lib/jafar/team-access';
import { sendTransactionalEmail } from '$lib/server/email/brevo';

/**
 * Uplift teammates of the Jafar Panel (ADR 0008): invitations, acceptance, removal, password sign-in, and
 * password reset. Teammates are not Supabase Auth users; their sessions live in the owner's session
 * registry. Every link is 32 random bytes of which only the SHA-256 is stored, consumed by one conditional
 * UPDATE so two clicks of the same link can never both succeed.
 */

const INVITATION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const PASSWORD_RESET_TTL_MS = 60 * 60 * 1000;
const BCRYPT_COST = 12;
// Compared against when no teammate matches, so a wrong email costs the same time as a wrong password.
// A fixed hash of a throwaway phrase at the same cost; it unlocks nothing.
const TIMING_DECOY_HASH = '$2b$12$Q5HjYRBg3ky0D6rrbR20Y.suKiQlhFGEV.GfTMpI3yMf9F45rh3tS';

type Client = SupabaseClient<Database>;

export type TeamMemberStatus = 'invited' | 'active';

export type TeamMemberSummary = {
	id: string;
	email: string;
	full_name: string | null;
	role: TeamRole;
	status: TeamMemberStatus;
	invited_at: string;
	invitation_expires_at: string | null;
	accepted_at: string | null;
	invited_by_email: string;
};

export type TeamMemberErrorCode =
	'owner_email' | 'already_on_team' | 'not_found' | 'invalid_or_expired' | 'email_failed';

export class TeamMemberError extends Error {
	constructor(
		public readonly code: TeamMemberErrorCode,
		message: string
	) {
		super(message);
		this.name = 'TeamMemberError';
	}
}

function hashToken(token: string) {
	return createHash('sha256').update(token).digest('hex');
}

function newToken() {
	const token = randomBytes(32).toString('base64url');
	return { token, hash: hashToken(token) };
}

function normalizeEmail(email: string) {
	return email.trim().toLowerCase();
}

function htmlEscape(value: string) {
	return value
		.replaceAll('&', '&amp;')
		.replaceAll('<', '&lt;')
		.replaceAll('>', '&gt;')
		.replaceAll('"', '&quot;')
		.replaceAll("'", '&#039;');
}

function maskEmail(email: string) {
	const [local, domain] = email.split('@');
	if (!domain) return '';
	return `${local.slice(0, 2)}•••@${domain}`;
}

function isUniqueViolation(error: { code?: string } | null) {
	return error?.code === '23505';
}

export function hashTeamPassword(password: string) {
	return bcrypt.hash(password, BCRYPT_COST);
}

const SUMMARY_COLUMNS =
	'id, email, full_name, role, status, invited_at, invitation_expires_at, accepted_at, invited_by_email';

function toSummary(row: Record<string, unknown>): TeamMemberSummary {
	return row as unknown as TeamMemberSummary;
}

export async function listTeamMembers(client: Client): Promise<TeamMemberSummary[]> {
	const { data, error } = await client
		.from('platform_team_members')
		.select(SUMMARY_COLUMNS)
		.neq('status', 'removed')
		.order('invited_at', { ascending: true });
	if (error) throw error;
	return (data ?? []).map(toSummary);
}

async function sendInvitationEmail(params: {
	email: string;
	role: TeamRole;
	origin: string;
	token: string;
}) {
	const link = new URL('/jafar/join', params.origin);
	link.searchParams.set('token', params.token);
	const role = TEAM_ROLE_LABELS[params.role];
	const subject = 'You’re invited to the Uplift team';
	const textContent = `Jafar has invited you to join the Uplift team as ${role}. Set your password and sign in: ${link.toString()}\n\nThis link expires in seven days.`;
	const htmlContent = `<p>Jafar has invited you to join the Uplift team as <strong>${htmlEscape(role)}</strong>.</p><p><a href="${htmlEscape(link.toString())}">Set your password and sign in</a></p><p>This link expires in seven days.</p>`;

	try {
		await sendTransactionalEmail({
			to: { email: params.email },
			subject,
			htmlContent,
			textContent
		});
	} catch (error) {
		console.error('A team invitation email could not be sent.', error);
		throw new TeamMemberError(
			'email_failed',
			'The invitation was saved, but the email could not be sent. Use Resend to try again.'
		);
	}
}

/**
 * Invites one person with a starting role. The email must not be the owner's or belong to someone already
 * invited or on the team. The record is saved before the email goes out, so a failed send can be resent.
 */
export async function inviteTeamMember(
	client: Client,
	params: { email: string; role: TeamRole; invitedBy: string; origin: string; ownerEmail: string }
): Promise<TeamMemberSummary> {
	const email = normalizeEmail(params.email);
	if (email === normalizeEmail(params.ownerEmail)) {
		throw new TeamMemberError('owner_email', 'That is your own sign-in email.');
	}

	const { token, hash } = newToken();
	const { data, error } = await client
		.from('platform_team_members')
		.insert({
			email,
			role: params.role,
			status: 'invited',
			invitation_token_hash: hash,
			invitation_expires_at: new Date(Date.now() + INVITATION_TTL_MS).toISOString(),
			invited_by_email: params.invitedBy
		})
		.select(SUMMARY_COLUMNS)
		.single();
	if (isUniqueViolation(error)) {
		throw new TeamMemberError(
			'already_on_team',
			'This person is already on your team or has an invitation waiting.'
		);
	}
	if (error || !data) throw error ?? new Error('The invitation could not be saved.');

	await sendInvitationEmail({ email, role: params.role, origin: params.origin, token });
	return toSummary(data);
}

/** A fresh link and seven more days for a waiting invitation; the previous link stops working. */
export async function resendTeamInvitation(
	client: Client,
	params: { memberId: string; origin: string }
): Promise<TeamMemberSummary> {
	const { token, hash } = newToken();
	const { data, error } = await client
		.from('platform_team_members')
		.update({
			invitation_token_hash: hash,
			invitation_expires_at: new Date(Date.now() + INVITATION_TTL_MS).toISOString(),
			invited_at: new Date().toISOString()
		})
		.eq('id', params.memberId)
		.eq('status', 'invited')
		.select(SUMMARY_COLUMNS)
		.maybeSingle();
	if (error) throw error;
	if (!data) throw new TeamMemberError('not_found', 'That invitation is no longer waiting.');

	const summary = toSummary(data);
	await sendInvitationEmail({
		email: summary.email,
		role: summary.role,
		origin: params.origin,
		token
	});
	return summary;
}

/**
 * Removes a teammate or cancels a waiting invitation. The record keeps its history but loses its password
 * and links, and every open session is revoked. Access already ends with the status change: the session
 * check requires an active teammate on every request.
 */
export async function removeTeamMember(
	client: Client,
	params: { memberId: string; removedBy: string }
): Promise<TeamMemberSummary> {
	const { data: current, error: readError } = await client
		.from('platform_team_members')
		.select(SUMMARY_COLUMNS)
		.eq('id', params.memberId)
		.neq('status', 'removed')
		.maybeSingle();
	if (readError) throw readError;
	if (!current) throw new TeamMemberError('not_found', 'That teammate is no longer on the team.');

	// Conditional on the status just read, so an invitation accepted a moment ago is not recorded as a
	// cancelled one: the second attempt finds nothing and reports it.
	const { data, error } = await client
		.from('platform_team_members')
		.update({
			status: 'removed',
			removed_at: new Date().toISOString(),
			removed_by_email: params.removedBy,
			password_hash: null,
			invitation_token_hash: null,
			invitation_expires_at: null,
			password_reset_token_hash: null,
			password_reset_expires_at: null
		})
		.eq('id', params.memberId)
		.eq('status', current.status)
		.select('id')
		.maybeSingle();
	if (error) throw error;
	if (!data)
		throw new TeamMemberError(
			'not_found',
			'That teammate changed just now. Refresh and try again.'
		);

	await revokeTeamMemberSessions(client, params.memberId, 'teammate_removed');
	return toSummary(current);
}

async function revokeTeamMemberSessions(client: Client, memberId: string, reason: string) {
	const { error } = await client
		.from('platform_owner_sessions')
		.update({ revoked_at: new Date().toISOString(), revoked_reason: reason })
		.eq('team_member_id', memberId)
		.is('revoked_at', null);
	if (error) console.error('A teammate’s sessions could not be revoked.', error);
}

/** What the join page may show about an invitation link before the person sets a password. */
export async function inspectTeamInvitation(
	client: Client,
	token: string
): Promise<{ valid: false } | { valid: true; emailHint: string; role: TeamRole }> {
	const { data, error } = await client
		.from('platform_team_members')
		.select('email, role, invitation_expires_at')
		.eq('invitation_token_hash', hashToken(token))
		.eq('status', 'invited')
		.maybeSingle();
	if (error) throw error;
	if (
		!data?.invitation_expires_at ||
		new Date(data.invitation_expires_at).getTime() <= Date.now()
	) {
		return { valid: false };
	}
	return { valid: true, emailHint: maskEmail(data.email), role: data.role as TeamRole };
}

/** Accepts an invitation once: sets the name and password and makes the teammate active. */
export async function acceptTeamInvitation(
	client: Client,
	params: { token: string; fullName: string; password: string }
): Promise<{ memberId: string; email: string }> {
	const passwordHash = await hashTeamPassword(params.password);
	const now = new Date().toISOString();
	const { data, error } = await client
		.from('platform_team_members')
		.update({
			status: 'active',
			full_name: params.fullName,
			password_hash: passwordHash,
			accepted_at: now,
			password_changed_at: now,
			invitation_token_hash: null,
			invitation_expires_at: null
		})
		.eq('invitation_token_hash', hashToken(params.token))
		.eq('status', 'invited')
		.gt('invitation_expires_at', now)
		.select('id, email')
		.maybeSingle();
	if (error) throw error;
	if (!data) {
		throw new TeamMemberError(
			'invalid_or_expired',
			'This invitation link has expired or was already used. Ask Jafar to send a new one.'
		);
	}
	return { memberId: data.id, email: data.email };
}

/**
 * The active teammate these credentials belong to, or null. Runs one bcrypt comparison whether or not the
 * email matches anyone, so response time does not reveal who is on the team.
 */
export async function verifyTeammateCredentials(
	client: Client,
	email: string,
	password: string
): Promise<{ memberId: string; email: string } | null> {
	const { data, error } = await client
		.from('platform_team_members')
		.select('id, email, password_hash')
		.eq('email', normalizeEmail(email))
		.eq('status', 'active')
		.maybeSingle();
	if (error) throw error;

	const matches = await bcrypt.compare(password, data?.password_hash ?? TIMING_DECOY_HASH);
	if (!data?.password_hash || !matches) return null;
	return { memberId: data.id, email: data.email };
}

/**
 * Emails a one-hour reset link to an active teammate. Says nothing either way about whether the email
 * belongs to one; a newer request replaces the previous link.
 */
export async function requestTeamPasswordReset(
	client: Client,
	params: { email: string; origin: string }
) {
	const { token, hash } = newToken();
	const { data, error } = await client
		.from('platform_team_members')
		.update({
			password_reset_token_hash: hash,
			password_reset_expires_at: new Date(Date.now() + PASSWORD_RESET_TTL_MS).toISOString()
		})
		.eq('email', normalizeEmail(params.email))
		.eq('status', 'active')
		.select('email')
		.maybeSingle();
	if (error) throw error;
	if (!data) return;

	const link = new URL('/jafar/reset-password', params.origin);
	link.searchParams.set('token', token);
	const subject = 'Reset your Uplift team password';
	const textContent = `Someone asked to reset the password for your Uplift team sign-in. Choose a new password: ${link.toString()}\n\nThis link works once and expires in one hour. If you did not ask for this, you can ignore this email.`;
	const htmlContent = `<p>Someone asked to reset the password for your Uplift team sign-in.</p><p><a href="${htmlEscape(link.toString())}">Choose a new password</a></p><p>This link works once and expires in one hour. If you did not ask for this, you can ignore this email.</p>`;
	try {
		await sendTransactionalEmail({ to: { email: data.email }, subject, htmlContent, textContent });
	} catch (error) {
		// Not surfaced: the answer must look the same whether or not the email exists.
		console.error('A team password reset email could not be sent.', error);
	}
}

/** Sets a new password from a reset link once, and signs the teammate out everywhere else. */
export async function completeTeamPasswordReset(
	client: Client,
	params: { token: string; password: string }
) {
	const passwordHash = await hashTeamPassword(params.password);
	const now = new Date().toISOString();
	const { data, error } = await client
		.from('platform_team_members')
		.update({
			password_hash: passwordHash,
			password_changed_at: now,
			password_reset_token_hash: null,
			password_reset_expires_at: null
		})
		.eq('password_reset_token_hash', hashToken(params.token))
		.eq('status', 'active')
		.gt('password_reset_expires_at', now)
		.select('id')
		.maybeSingle();
	if (error) throw error;
	if (!data) {
		throw new TeamMemberError(
			'invalid_or_expired',
			'This reset link has expired or was already used. Ask for a new one.'
		);
	}
	await revokeTeamMemberSessions(client, data.id, 'password_reset');
}
