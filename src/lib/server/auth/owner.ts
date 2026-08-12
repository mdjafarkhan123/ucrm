import { createHmac, timingSafeEqual } from 'node:crypto';
import { redirect, type RequestEvent } from '@sveltejs/kit';
import { compareSync } from 'bcryptjs';
import { getServerEnv } from '$lib/server/env';

const OWNER_SESSION_COOKIE = 'jafar_session';
const OWNER_SESSION_TTL_SECONDS = 60 * 60 * 8;
const OWNER_STEP_UP_COOKIE = 'jafar_step_up';
const OWNER_STEP_UP_TTL_SECONDS = 60 * 5;

type OwnerSession = {
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

function encodeSession(session: OwnerSession, secret: string) {
	const payload = Buffer.from(JSON.stringify(session)).toString('base64url');
	return `${payload}.${sign(payload, secret)}`;
}

function decodeSession(value: string, secret: string): OwnerSession | null {
	const [payload, signature] = value.split('.');
	if (!payload || !signature) return null;

	const expected = sign(payload, secret);
	const providedBuffer = Buffer.from(signature);
	const expectedBuffer = Buffer.from(expected);
	if (
		providedBuffer.length !== expectedBuffer.length ||
		!timingSafeEqual(providedBuffer, expectedBuffer)
	) {
		return null;
	}

	try {
		const session = JSON.parse(Buffer.from(payload, 'base64url').toString()) as OwnerSession;
		if (
			typeof session.email !== 'string' ||
			typeof session.expiresAt !== 'number' ||
			session.expiresAt <= Date.now()
		) {
			return null;
		}

		return session;
	} catch {
		return null;
	}
}

export function verifyOwnerCredentials(email: string, password: string) {
	const config = getOwnerConfig();
	return email.trim().toLowerCase() === config.email && compareSync(password, config.passwordHash);
}

export function getOwnerSession(event: RequestEvent) {
	const value = event.cookies.get(OWNER_SESSION_COOKIE);
	if (!value) return null;

	try {
		const { secret, email } = getOwnerConfig();
		const session = decodeSession(value, secret);
		if (!session || session.email !== email) return null;
		return session;
	} catch {
		return null;
	}
}

export function setOwnerSession(event: RequestEvent, email: string) {
	const { secret } = getOwnerConfig();
	const session: OwnerSession = {
		email: email.trim().toLowerCase(),
		expiresAt: Date.now() + OWNER_SESSION_TTL_SECONDS * 1000
	};

	event.cookies.set(OWNER_SESSION_COOKIE, encodeSession(session, secret), {
		httpOnly: true,
		secure: !event.url.hostname.includes('localhost') && !event.url.hostname.includes('127.0.0.1'),
		sameSite: 'strict',
		path: '/',
		maxAge: OWNER_SESSION_TTL_SECONDS
	});
}

export function clearOwnerSession(event: RequestEvent) {
	event.cookies.delete(OWNER_SESSION_COOKIE, { path: '/' });
}

export function signOwnerStepUp(event: RequestEvent, email: string) {
	const { secret } = getOwnerConfig();
	const stepUp: OwnerSession = {
		email: email.trim().toLowerCase(),
		expiresAt: Date.now() + OWNER_STEP_UP_TTL_SECONDS * 1000
	};

	event.cookies.set(OWNER_STEP_UP_COOKIE, encodeSession(stepUp, secret), {
		httpOnly: true,
		secure: !event.url.hostname.includes('localhost') && !event.url.hostname.includes('127.0.0.1'),
		sameSite: 'strict',
		path: '/',
		maxAge: OWNER_STEP_UP_TTL_SECONDS
	});
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
	const stepUp = decodeSession(value, secret);
	return stepUp !== null && stepUp.email === session.email;
}

export function requireOwner(event: RequestEvent) {
	const session = getOwnerSession(event);
	if (!session) throw redirect(303, '/jafar/login');
	return session;
}
