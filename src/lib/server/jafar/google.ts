import { randomUUID } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import { env } from '$env/dynamic/private';
import type { Database } from '$lib/database.types';
import {
	GoogleCryptoError,
	decryptGoogleTokens,
	encryptGoogleTokens,
	getGoogleKeyring,
	type GoogleEnvelope,
	type GoogleTokens
} from '$lib/server/jafar/google-crypto';

// Jafar business management E5: Jafar's own Google account (an OAuth web-app client) and the three things UCRM asks
// of it -- make a Calendar event with its own Meet link for a booking, move it, delete it. Google keeps a refresh
// token until it is revoked, so a refresh only replaces the short-lived access token.

type Client = SupabaseClient<Database>;

const REFRESH_EARLY_MS = 60_000;
const SCOPES = 'openid email profile https://www.googleapis.com/auth/calendar.events';

/** Where Google lives; the test suite points these at a stand-in server. */
const standIn = () => (env.GOOGLE_OAUTH_BASE_URL || '').replace(/\/$/, '');
const authorizeEndpoint = () =>
	standIn() ? `${standIn()}/authorize` : 'https://accounts.google.com/o/oauth2/v2/auth';
const tokenEndpoint = () =>
	standIn() ? `${standIn()}/token` : 'https://oauth2.googleapis.com/token';
const profileEndpoint = () =>
	standIn() ? `${standIn()}/userinfo` : 'https://openidconnect.googleapis.com/v1/userinfo';
const calendarBase = () =>
	(env.GOOGLE_API_BASE_URL || 'https://www.googleapis.com/calendar/v3').replace(/\/$/, '');

export class GoogleError extends Error {
	constructor(
		message: string,
		public readonly code: 'not_connected' | 'needs_reconnect' | 'rejected' | 'unavailable'
	) {
		super(message);
		this.name = 'GoogleError';
	}
}

export function googleConfigured() {
	try {
		getGoogleKeyring();
	} catch {
		return false;
	}
	return Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET);
}

export const googleRedirectUri = (origin: string) => `${origin}/api/jafar/booking/google/callback`;

export function googleAuthorizeUrl(origin: string, state: string) {
	const url = new URL(authorizeEndpoint());
	url.searchParams.set('response_type', 'code');
	url.searchParams.set('client_id', env.GOOGLE_CLIENT_ID ?? '');
	url.searchParams.set('redirect_uri', googleRedirectUri(origin));
	url.searchParams.set('scope', SCOPES);
	url.searchParams.set('state', state);
	// Offline access with a fresh consent is what makes Google hand back a refresh token every time.
	url.searchParams.set('access_type', 'offline');
	url.searchParams.set('prompt', 'consent');
	return url.toString();
}

type TokenReply = { access_token: string; refresh_token?: string; expires_in: number };

async function tokenRequest(params: Record<string, string>): Promise<TokenReply> {
	let response: Response;
	try {
		response = await fetch(tokenEndpoint(), {
			method: 'POST',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: new URLSearchParams({
				...params,
				client_id: env.GOOGLE_CLIENT_ID ?? '',
				client_secret: env.GOOGLE_CLIENT_SECRET ?? ''
			}),
			signal: AbortSignal.timeout(10_000)
		});
	} catch {
		throw new GoogleError('Google could not be reached.', 'unavailable');
	}
	if (response.status >= 500) throw new GoogleError('Google is having trouble.', 'unavailable');
	const body = (await response.json().catch(() => null)) as Partial<TokenReply> | null;
	if (!response.ok || !body?.access_token || !body.expires_in)
		throw new GoogleError('Google did not accept the sign-in.', 'rejected');
	return body as TokenReply;
}

type ConnectionRow = Database['public']['Tables']['platform_google_connection']['Row'];

const envelopeOf = (row: ConnectionRow): GoogleEnvelope => ({
	keyId: row.credential_key_id,
	nonce: row.credential_nonce,
	ciphertext: row.credential_ciphertext,
	tag: row.credential_tag
});

const envelopeColumns = (envelope: GoogleEnvelope) => ({
	credential_key_id: envelope.keyId,
	credential_nonce: envelope.nonce,
	credential_ciphertext: envelope.ciphertext,
	credential_tag: envelope.tag
});

export type GoogleStatus = {
	configured: boolean;
	connected: boolean;
	needs_reconnect: boolean;
	email: string | null;
	name: string | null;
	connected_at: string | null;
};

export async function googleStatus(client: Client): Promise<GoogleStatus> {
	const { data, error } = await client
		.from('platform_google_connection')
		.select('google_email, google_name, status, connected_at')
		.maybeSingle();
	if (error) throw error;
	return {
		configured: googleConfigured(),
		connected: Boolean(data),
		needs_reconnect: data?.status === 'needs_reconnect',
		email: data?.google_email ?? null,
		name: data?.google_name ?? null,
		connected_at: data?.connected_at ?? null
	};
}

async function googleApi<T>(
	token: string,
	method: string,
	url: string,
	body?: unknown
): Promise<T> {
	let response: Response;
	try {
		response = await fetch(url, {
			method,
			headers: {
				Authorization: `Bearer ${token}`,
				...(body ? { 'Content-Type': 'application/json' } : {})
			},
			body: body ? JSON.stringify(body) : undefined,
			signal: AbortSignal.timeout(10_000)
		});
	} catch {
		throw new GoogleError('Google could not be reached.', 'unavailable');
	}
	// An event Google no longer has counts as already deleted.
	if ((response.status === 404 || response.status === 410) && method === 'DELETE')
		return undefined as T;
	if (response.status === 401)
		throw new GoogleError('Google needs to be connected again.', 'needs_reconnect');
	if (response.status === 429 || response.status >= 500)
		throw new GoogleError('Google is busy or having trouble.', 'unavailable');
	if (!response.ok)
		throw new GoogleError(`Google refused the request (${response.status}).`, 'rejected');
	if (response.status === 204) return undefined as T;
	return (await response.json()) as T;
}

/** Finishes the sign-in Google sent Jafar back from: keeps his tokens, replacing any earlier connection. */
export async function connectGoogle(
	client: Client,
	code: string,
	origin: string,
	actorEmail: string
) {
	const reply = await tokenRequest({
		grant_type: 'authorization_code',
		code,
		redirect_uri: googleRedirectUri(origin)
	});
	// Without a refresh token the connection would lapse within the hour.
	if (!reply.refresh_token) throw new GoogleError('Google gave no lasting access.', 'rejected');
	const me = await googleApi<{ sub: string; email: string; name?: string }>(
		reply.access_token,
		'GET',
		profileEndpoint()
	);
	const { error } = await client.from('platform_google_connection').upsert({
		id: true,
		google_user_id: me.sub,
		google_email: me.email,
		google_name: me.name?.slice(0, 200) ?? null,
		...envelopeColumns(
			encryptGoogleTokens({ accessToken: reply.access_token, refreshToken: reply.refresh_token })
		),
		access_expires_at: new Date(Date.now() + reply.expires_in * 1000).toISOString(),
		status: 'connected',
		connected_by_email: actorEmail,
		connected_at: new Date().toISOString()
	});
	if (error) throw error;
}

/** Removes the connection. Events already made stay in Google Calendar and on their bookings. */
export async function disconnectGoogle(client: Client) {
	const { error } = await client.from('platform_google_connection').delete().eq('id', true);
	if (error) throw error;
}

async function markNeedsReconnect(client: Client) {
	await client
		.from('platform_google_connection')
		.update({ status: 'needs_reconnect' })
		.eq('id', true);
}

/** A working access token, refreshed first when it is about to lapse. */
async function accessToken(client: Client): Promise<string> {
	if (!googleConfigured())
		throw new GoogleError('Google is not set up on this server.', 'not_connected');
	const { data: row, error } = await client
		.from('platform_google_connection')
		.select('*')
		.maybeSingle();
	if (error) throw error;
	if (!row) throw new GoogleError('Google is not connected.', 'not_connected');
	if (row.status === 'needs_reconnect')
		throw new GoogleError('Google needs to be connected again.', 'needs_reconnect');

	let tokens: GoogleTokens;
	try {
		tokens = decryptGoogleTokens(envelopeOf(row));
	} catch (cryptoError) {
		if (cryptoError instanceof GoogleCryptoError) {
			await markNeedsReconnect(client);
			throw new GoogleError('Google needs to be connected again.', 'needs_reconnect');
		}
		throw cryptoError;
	}
	if (Date.parse(row.access_expires_at) - Date.now() > REFRESH_EARLY_MS) return tokens.accessToken;

	let reply: TokenReply;
	try {
		reply = await tokenRequest({ grant_type: 'refresh_token', refresh_token: tokens.refreshToken });
	} catch (refreshError) {
		// Google answers a revoked or expired refresh token with a refusal: only a fresh sign-in helps.
		if (refreshError instanceof GoogleError && refreshError.code === 'rejected') {
			await markNeedsReconnect(client);
			throw new GoogleError('Google needs to be connected again.', 'needs_reconnect');
		}
		throw refreshError;
	}
	const saved = await client
		.from('platform_google_connection')
		.update({
			...envelopeColumns(
				encryptGoogleTokens({
					accessToken: reply.access_token,
					refreshToken: reply.refresh_token ?? tokens.refreshToken
				})
			),
			access_expires_at: new Date(Date.now() + reply.expires_in * 1000).toISOString()
		})
		.eq('id', true)
		.eq('credential_nonce', row.credential_nonce)
		.select('id');
	if (saved.error) throw saved.error;
	return reply.access_token;
}

/** Runs one Google call as Jafar; a refused token marks the connection as needing a fresh sign-in. */
async function asJafar<T>(client: Client, call: (token: string) => Promise<T>): Promise<T> {
	try {
		return await call(await accessToken(client));
	} catch (error) {
		if (error instanceof GoogleError && error.code === 'needs_reconnect')
			await markNeedsReconnect(client);
		throw error;
	}
}

export type MeetInput = { topic: string; startsAt: string; endsAt: string };

const eventTimes = ({ topic, startsAt, endsAt }: MeetInput) => ({
	summary: topic.slice(0, 200),
	start: { dateTime: new Date(startsAt).toISOString(), timeZone: 'UTC' },
	end: { dateTime: new Date(endsAt).toISOString(), timeZone: 'UTC' }
});

const eventUrl = (eventId: string, query: string) =>
	`${calendarBase()}/calendars/primary/events/${encodeURIComponent(eventId)}?${query}`;

type EventReply = {
	id: string;
	hangoutLink?: string;
	conferenceData?: {
		createRequest?: { status?: { statusCode?: string } };
		entryPoints?: { entryPointType?: string; uri?: string }[];
	};
};

const joinUrlOf = (event: EventReply) =>
	event.hangoutLink ??
	event.conferenceData?.entryPoints?.find((point) => point.entryPointType === 'video')?.uri ??
	null;

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * A new Calendar event on Jafar's own calendar with its own Meet link. The visitor is not invited -- UCRM's own emails
 * carry the link -- and Google sends nobody anything (`sendUpdates=none`).
 */
export function createMeetEvent(client: Client, input: MeetInput) {
	return asJafar(client, async (token) => {
		let event = await googleApi<EventReply>(
			token,
			'POST',
			`${calendarBase()}/calendars/primary/events?conferenceDataVersion=1&sendUpdates=none`,
			{
				...eventTimes(input),
				conferenceData: {
					createRequest: {
						requestId: randomUUID(),
						conferenceSolutionKey: { type: 'hangoutsMeet' }
					}
				}
			}
		);
		// Google may still be making the link: look again briefly before giving up.
		for (let attempt = 0; attempt < 3 && !joinUrlOf(event); attempt += 1) {
			await wait(600);
			event = await googleApi<EventReply>(
				token,
				'GET',
				eventUrl(event.id, 'conferenceDataVersion=1')
			);
		}
		const joinUrl = joinUrlOf(event);
		if (!joinUrl) {
			await googleApi<void>(token, 'DELETE', eventUrl(event.id, 'sendUpdates=none')).catch(
				() => undefined
			);
			throw new GoogleError('Google did not make a Meet link.', 'unavailable');
		}
		return { meetingId: event.id, joinUrl };
	});
}

export const moveMeetEvent = (client: Client, eventId: string, input: MeetInput) =>
	asJafar(client, (token) =>
		googleApi<void>(token, 'PATCH', eventUrl(eventId, 'sendUpdates=none'), eventTimes(input))
	);

/** Deleting an event Google no longer has counts as done. */
export const deleteMeetEvent = (client: Client, eventId: string) =>
	asJafar(client, (token) =>
		googleApi<void>(token, 'DELETE', eventUrl(eventId, 'sendUpdates=none'))
	);
