import { createHmac, timingSafeEqual } from 'node:crypto';
import { redirect, type RequestEvent } from '@sveltejs/kit';
import { compareSync } from 'bcryptjs';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	TEAM_ROLES,
	effectiveTeamAccess,
	storedTeamAccessAdjustments,
	type TeamAccess,
	type TeamRole
} from '$lib/jafar/team-access';

const OWNER_SESSION_COOKIE = 'jafar_session';
const OWNER_SESSION_TTL_SECONDS = 60 * 60 * 8;
const OWNER_STEP_UP_COOKIE = 'jafar_step_up';
const OWNER_STEP_UP_TTL_SECONDS = 60 * 5;
const SESSION_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Whoever holds a live `/jafar` session: the platform owner (`role` null) or an invited teammate
 * (ADR 0008). `email` is the actor recorded in audit history either way.
 */
export type OwnerSession = {
	email: string;
	sessionId: string;
	role: TeamRole | null;
	/** A teammate's role with Jafar's adjustments (D2); null for the owner, who has everything. */
	access: TeamAccess | null;
	memberId: string | null;
	name: string | null;
};

type OwnerStepUp = {
	email: string;
	expiresAt: number;
};

function getOwnerConfig() {
	const {
		SUPER_ADMIN_EMAIL: email,
		SUPER_ADMIN_PASSWORD_HASH: passwordHash,
		SESSION_SECRET: secret
	} = getServerEnv();

	return { email, passwordHash, secret };
}

function sign(value: string, secret: string) {
	return createHmac('sha256', secret).update(value).digest('base64url');
}

function verifySignature(value: string, signature: string, secret: string) {
	const expected = sign(value, secret);
	const providedBuffer = Buffer.from(signature);
	const expectedBuffer = Buffer.from(expected);
	return (
		providedBuffer.length === expectedBuffer.length &&
		timingSafeEqual(providedBuffer, expectedBuffer)
	);
}

function encodeSignedSessionId(sessionId: string, secret: string) {
	return `${sessionId}.${sign(sessionId, secret)}`;
}

/**
 * The cookie only ever carries a session id, never session content -- the signature just proves the
 * browser didn't tamper with or invent the id before it's looked up in the session registry, which
 * remains the sole source of truth for whether the session is actually valid.
 */
function decodeSignedSessionId(value: string, secret: string): string | null {
	const [sessionId, signature] = value.split('.');
	if (!sessionId || !signature || !SESSION_ID_PATTERN.test(sessionId)) return null;
	return verifySignature(sessionId, signature, secret) ? sessionId : null;
}

function encodeStepUp(stepUp: OwnerStepUp, secret: string) {
	const payload = Buffer.from(JSON.stringify(stepUp)).toString('base64url');
	return `${payload}.${sign(payload, secret)}`;
}

function decodeStepUp(value: string, secret: string): OwnerStepUp | null {
	const [payload, signature] = value.split('.');
	if (!payload || !signature || !verifySignature(payload, signature, secret)) return null;

	try {
		const stepUp = JSON.parse(Buffer.from(payload, 'base64url').toString()) as OwnerStepUp;
		if (
			typeof stepUp.email !== 'string' ||
			typeof stepUp.expiresAt !== 'number' ||
			stepUp.expiresAt <= Date.now()
		) {
			return null;
		}
		return stepUp;
	} catch {
		return null;
	}
}

function cookieOptions(event: RequestEvent, maxAgeSeconds: number) {
	return {
		httpOnly: true as const,
		secure: !event.url.hostname.includes('localhost') && !event.url.hostname.includes('127.0.0.1'),
		sameSite: 'strict' as const,
		path: '/',
		maxAge: maxAgeSeconds
	};
}

export function verifyOwnerCredentials(email: string, password: string) {
	const config = getOwnerConfig();
	return email.trim().toLowerCase() === config.email && compareSync(password, config.passwordHash);
}

/** Whether this email is the configured platform owner's, which no teammate may use. */
export function isOwnerEmail(email: string) {
	return email.trim().toLowerCase() === getOwnerConfig().email;
}

/** A keyed hash, never the raw IP, so the rate-limit bucket table never stores caller identity. */
export function ownerLoginRateLimitBucketKey(ipAddress: string) {
	const { secret } = getOwnerConfig();
	return `owner_login:${sign(ipAddress, secret)}`;
}

/**
 * The signed session id from the cookie, checked for tampering but not looked up in the registry -- only
 * good enough to key a rate-limit bucket, never to grant access. A forged or missing cookie gives null.
 */
export function ownerSessionIdFromCookie(event: RequestEvent): string | null {
	const value = event.cookies.get(OWNER_SESSION_COOKIE);
	if (!value) return null;
	return decodeSignedSessionId(value, getOwnerConfig().secret);
}

export async function recordOwnerLoginAttempt(outcome: 'succeeded' | 'failed' | 'rate_limited') {
	try {
		const client = getOwnerSupabaseClient();
		const { error } = await client.from('platform_owner_login_attempts').insert({ outcome });
		if (error) throw error;
	} catch (error) {
		console.error('The login attempt could not be recorded.', error);
	}
}

/**
 * The narrow authentication seam: the only place a session id is ever resolved against the
 * registry. Callers must not reach for their own service-role client until this resolves a session,
 * so nothing downstream can run ahead of an unrevoked, unexpired session check. Any registry lookup
 * failure fails closed (returns null) rather than letting a database hiccup fall open into access.
 */
export function getOwnerSession(event: RequestEvent): Promise<OwnerSession | null> {
	// The front-door gate resolves the session first; the route's own check reuses that answer through
	// `locals` instead of asking the registry a second time in the same request.
	const { locals } = event;
	if (!locals) return resolveOwnerSession(event);
	locals.ownerSession ??= resolveOwnerSession(event);
	return locals.ownerSession;
}

async function resolveOwnerSession(event: RequestEvent): Promise<OwnerSession | null> {
	const value = event.cookies.get(OWNER_SESSION_COOKIE);
	if (!value) return null;

	const { secret, email: configuredEmail } = getOwnerConfig();
	const sessionId = decodeSignedSessionId(value, secret);
	if (!sessionId) return null;

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client
			.from('platform_owner_sessions')
			.select(
				'owner_email, expires_at, revoked_at, team_member_id, platform_team_members(email, role, status, full_name, area_adjustments, action_grants)'
			)
			.eq('id', sessionId)
			.maybeSingle();
		if (error) throw error;
		if (!data || data.revoked_at) return null;
		if (new Date(data.expires_at).getTime() <= Date.now()) return null;

		if (!data.team_member_id) {
			if (data.owner_email !== configuredEmail) return null;
			return {
				email: data.owner_email,
				sessionId,
				role: null,
				access: null,
				memberId: null,
				name: null
			};
		}

		// A teammate passes only while still active under the same email, so removal ends access on the
		// very next request even before their session rows are revoked.
		const member = Array.isArray(data.platform_team_members)
			? data.platform_team_members[0]
			: data.platform_team_members;
		if (!member || member.status !== 'active' || member.email !== data.owner_email) return null;
		if (!(TEAM_ROLES as readonly string[]).includes(member.role)) return null;

		return {
			email: member.email,
			sessionId,
			role: member.role as TeamRole,
			access: effectiveTeamAccess(
				member.role as TeamRole,
				storedTeamAccessAdjustments(member.area_adjustments, member.action_grants)
			),
			memberId: data.team_member_id,
			name: member.full_name
		};
	} catch (error) {
		console.error('The owner session registry could not be checked.', error);
		return null;
	}
}

/**
 * Issues a fresh session on every successful login. If the browser already presented a session
 * cookie, that session is revoked first ("rotated") so a login can never leave two live sessions
 * for the same browser -- one always replaces the other. A teammate's session names their record.
 */
export async function setOwnerSession(
	event: RequestEvent,
	email: string,
	teamMemberId: string | null = null
) {
	const { secret } = getOwnerConfig();
	const client = getOwnerSupabaseClient();
	const normalizedEmail = email.trim().toLowerCase();
	if (event.locals) delete event.locals.ownerSession;

	const existingValue = event.cookies.get(OWNER_SESSION_COOKIE);
	const previousSessionId = existingValue ? decodeSignedSessionId(existingValue, secret) : null;
	if (previousSessionId) {
		const { error } = await client
			.from('platform_owner_sessions')
			.update({ revoked_at: new Date().toISOString(), revoked_reason: 'rotated' })
			.eq('id', previousSessionId)
			.is('revoked_at', null);
		if (error) console.error('The previous owner session could not be rotated out.', error);
	}

	const expiresAt = new Date(Date.now() + OWNER_SESSION_TTL_SECONDS * 1000).toISOString();
	const { data, error } = await client
		.from('platform_owner_sessions')
		.insert({ owner_email: normalizedEmail, expires_at: expiresAt, team_member_id: teamMemberId })
		.select('id')
		.single();
	if (error || !data) throw error ?? new Error('The owner session could not be created.');

	event.cookies.set(
		OWNER_SESSION_COOKIE,
		encodeSignedSessionId(data.id, secret),
		cookieOptions(event, OWNER_SESSION_TTL_SECONDS)
	);
}

export async function clearOwnerSession(event: RequestEvent) {
	const value = event.cookies.get(OWNER_SESSION_COOKIE);
	event.cookies.delete(OWNER_SESSION_COOKIE, { path: '/' });
	if (event.locals) delete event.locals.ownerSession;
	if (!value) return;

	const { secret } = getOwnerConfig();
	const sessionId = decodeSignedSessionId(value, secret);
	if (!sessionId) return;

	try {
		const client = getOwnerSupabaseClient();
		const { error } = await client
			.from('platform_owner_sessions')
			.update({ revoked_at: new Date().toISOString(), revoked_reason: 'logout' })
			.eq('id', sessionId)
			.is('revoked_at', null);
		if (error) throw error;
	} catch (error) {
		console.error('The owner session could not be revoked on logout.', error);
	}
}

export function signOwnerStepUp(event: RequestEvent, email: string) {
	const { secret } = getOwnerConfig();
	const stepUp: OwnerStepUp = {
		email: email.trim().toLowerCase(),
		expiresAt: Date.now() + OWNER_STEP_UP_TTL_SECONDS * 1000
	};

	event.cookies.set(
		OWNER_STEP_UP_COOKIE,
		encodeStepUp(stepUp, secret),
		cookieOptions(event, OWNER_STEP_UP_TTL_SECONDS)
	);
}

/**
 * Single-use: a valid step-up is consumed (cleared) whether or not the caller
 * proceeds, so one password reconfirmation authorizes exactly one high-impact action.
 */
export function consumeOwnerStepUp(event: RequestEvent, session: OwnerSession) {
	const value = event.cookies.get(OWNER_STEP_UP_COOKIE);
	event.cookies.delete(OWNER_STEP_UP_COOKIE, { path: '/' });
	if (!value) return false;

	const { secret } = getOwnerConfig();
	const stepUp = decodeStepUp(value, secret);
	// Step-up reconfirms the owner's own password, so it never authorizes a teammate (ADR 0008).
	return session.role === null && stepUp !== null && stepUp.email === session.email;
}

export async function requireOwner(event: RequestEvent) {
	const session = await getOwnerSession(event);
	if (!session) throw redirect(303, '/jafar/login');
	return session;
}
