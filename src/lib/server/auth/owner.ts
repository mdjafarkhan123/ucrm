import { createHmac, timingSafeEqual } from 'node:crypto';
import { redirect, type RequestEvent } from '@sveltejs/kit';
import { compareSync } from 'bcryptjs';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

const OWNER_SESSION_COOKIE = 'jafar_session';
const OWNER_SESSION_TTL_SECONDS = 60 * 60 * 8;
const OWNER_STEP_UP_COOKIE = 'jafar_step_up';
const OWNER_STEP_UP_TTL_SECONDS = 60 * 5;
const SESSION_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type OwnerSession = {
	email: string;
	sessionId: string;
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
		providedBuffer.length === expectedBuffer.length && timingSafeEqual(providedBuffer, expectedBuffer)
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

/** A keyed hash, never the raw IP, so the rate-limit bucket table never stores caller identity. */
export function ownerLoginRateLimitBucketKey(ipAddress: string) {
	const { secret } = getOwnerConfig();
	return `owner_login:${sign(ipAddress, secret)}`;
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
export async function getOwnerSession(event: RequestEvent): Promise<OwnerSession | null> {
	const value = event.cookies.get(OWNER_SESSION_COOKIE);
	if (!value) return null;

	const { secret, email: configuredEmail } = getOwnerConfig();
	const sessionId = decodeSignedSessionId(value, secret);
	if (!sessionId) return null;

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client
			.from('platform_owner_sessions')
			.select('owner_email, expires_at, revoked_at')
			.eq('id', sessionId)
			.maybeSingle();
		if (error) throw error;
		if (!data || data.revoked_at) return null;
		if (new Date(data.expires_at).getTime() <= Date.now()) return null;
		if (data.owner_email !== configuredEmail) return null;

		return { email: data.owner_email, sessionId };
	} catch (error) {
		console.error('The owner session registry could not be checked.', error);
		return null;
	}
}

/**
 * Issues a fresh session on every successful login. If the browser already presented a session
 * cookie, that session is revoked first ("rotated") so a login can never leave two live sessions
 * for the same browser -- one always replaces the other.
 */
export async function setOwnerSession(event: RequestEvent, email: string) {
	const { secret } = getOwnerConfig();
	const client = getOwnerSupabaseClient();
	const normalizedEmail = email.trim().toLowerCase();

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
		.insert({ owner_email: normalizedEmail, expires_at: expiresAt })
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
	return stepUp !== null && stepUp.email === session.email;
}

export async function requireOwner(event: RequestEvent) {
	const session = await getOwnerSession(event);
	if (!session) throw redirect(303, '/jafar/login');
	return session;
}
