import type { SupabaseClient } from '@supabase/supabase-js';
import { env } from '$env/dynamic/private';
import type { Database } from '$lib/database.types';
import {
	ZoomCryptoError,
	decryptZoomTokens,
	encryptZoomTokens,
	getZoomKeyring,
	type ZoomEnvelope,
	type ZoomTokens
} from '$lib/server/jafar/zoom-crypto';

// Jafar business management E4b: Jafar's own Zoom account (a user-managed OAuth app, Zoom's "end-user authorization")
// and the three things UCRM asks of it -- make a meeting for a booking, move it, delete it. Zoom replaces the
// refresh token on every refresh, so a refresh is saved only if nobody else saved one first.

type Client = SupabaseClient<Database>;

const REFRESH_EARLY_MS = 60_000;

/** Where Zoom lives; the test suite points these at a stand-in server. */
const oauthBase = () => (env.ZOOM_OAUTH_BASE_URL || 'https://zoom.us').replace(/\/$/, '');
const apiBase = () => (env.ZOOM_API_BASE_URL || 'https://api.zoom.us/v2').replace(/\/$/, '');

export class ZoomError extends Error {
	constructor(
		message: string,
		public readonly code: 'not_connected' | 'needs_reconnect' | 'rejected' | 'unavailable'
	) {
		super(message);
		this.name = 'ZoomError';
	}
}

export function zoomConfigured() {
	try {
		getZoomKeyring();
	} catch {
		return false;
	}
	return Boolean(env.ZOOM_CLIENT_ID && env.ZOOM_CLIENT_SECRET);
}

export const zoomRedirectUri = (origin: string) => `${origin}/api/jafar/booking/zoom/callback`;

export function zoomAuthorizeUrl(origin: string, state: string) {
	const url = new URL(`${oauthBase()}/oauth/authorize`);
	url.searchParams.set('response_type', 'code');
	url.searchParams.set('client_id', env.ZOOM_CLIENT_ID ?? '');
	url.searchParams.set('redirect_uri', zoomRedirectUri(origin));
	url.searchParams.set('state', state);
	return url.toString();
}

type TokenReply = { access_token: string; refresh_token: string; expires_in: number };

async function tokenRequest(params: Record<string, string>): Promise<TokenReply> {
	const basic = Buffer.from(`${env.ZOOM_CLIENT_ID}:${env.ZOOM_CLIENT_SECRET}`).toString('base64');
	let response: Response;
	try {
		response = await fetch(`${oauthBase()}/oauth/token`, {
			method: 'POST',
			headers: {
				Authorization: `Basic ${basic}`,
				'Content-Type': 'application/x-www-form-urlencoded'
			},
			body: new URLSearchParams(params),
			signal: AbortSignal.timeout(10_000)
		});
	} catch {
		throw new ZoomError('Zoom could not be reached.', 'unavailable');
	}
	if (response.status >= 500) throw new ZoomError('Zoom is having trouble.', 'unavailable');
	const body = (await response.json().catch(() => null)) as Partial<TokenReply> | null;
	if (!response.ok || !body?.access_token || !body.refresh_token || !body.expires_in)
		throw new ZoomError('Zoom did not accept the sign-in.', 'rejected');
	return body as TokenReply;
}

type ConnectionRow = Database['public']['Tables']['platform_zoom_connection']['Row'];

const envelopeOf = (row: ConnectionRow): ZoomEnvelope => ({
	keyId: row.credential_key_id,
	nonce: row.credential_nonce,
	ciphertext: row.credential_ciphertext,
	tag: row.credential_tag
});

const envelopeColumns = (envelope: ZoomEnvelope) => ({
	credential_key_id: envelope.keyId,
	credential_nonce: envelope.nonce,
	credential_ciphertext: envelope.ciphertext,
	credential_tag: envelope.tag
});

export type ZoomStatus = {
	configured: boolean;
	connected: boolean;
	needs_reconnect: boolean;
	email: string | null;
	name: string | null;
	connected_at: string | null;
};

export async function zoomStatus(client: Client): Promise<ZoomStatus> {
	const { data, error } = await client
		.from('platform_zoom_connection')
		.select('zoom_email, zoom_name, status, connected_at')
		.maybeSingle();
	if (error) throw error;
	return {
		configured: zoomConfigured(),
		connected: Boolean(data),
		needs_reconnect: data?.status === 'needs_reconnect',
		email: data?.zoom_email ?? null,
		name: data?.zoom_name ?? null,
		connected_at: data?.connected_at ?? null
	};
}

/** Finishes the sign-in Zoom sent Jafar back from: keeps his tokens, replacing any earlier connection. */
export async function connectZoom(
	client: Client,
	code: string,
	origin: string,
	actorEmail: string
) {
	const reply = await tokenRequest({
		grant_type: 'authorization_code',
		code,
		redirect_uri: zoomRedirectUri(origin)
	});
	const me = await zoomApi<{ id: string; email: string; display_name?: string }>(
		reply.access_token,
		'GET',
		'/users/me'
	);
	const { error } = await client.from('platform_zoom_connection').upsert({
		id: true,
		zoom_user_id: me.id,
		zoom_email: me.email,
		zoom_name: me.display_name?.slice(0, 200) ?? null,
		...envelopeColumns(
			encryptZoomTokens({ accessToken: reply.access_token, refreshToken: reply.refresh_token })
		),
		access_expires_at: new Date(Date.now() + reply.expires_in * 1000).toISOString(),
		status: 'connected',
		connected_by_email: actorEmail,
		connected_at: new Date().toISOString()
	});
	if (error) throw error;
}

/** Removes the connection. Meetings already made stay in Zoom and on their bookings. */
export async function disconnectZoom(client: Client) {
	const { error } = await client.from('platform_zoom_connection').delete().eq('id', true);
	if (error) throw error;
}

async function markNeedsReconnect(client: Client) {
	await client
		.from('platform_zoom_connection')
		.update({ status: 'needs_reconnect' })
		.eq('id', true);
}

/** A working access token, refreshed first when it is about to lapse. */
async function accessToken(client: Client): Promise<string> {
	if (!zoomConfigured()) throw new ZoomError('Zoom is not set up on this server.', 'not_connected');
	const { data: row, error } = await client
		.from('platform_zoom_connection')
		.select('*')
		.maybeSingle();
	if (error) throw error;
	if (!row) throw new ZoomError('Zoom is not connected.', 'not_connected');
	if (row.status === 'needs_reconnect')
		throw new ZoomError('Zoom needs to be connected again.', 'needs_reconnect');

	let tokens: ZoomTokens;
	try {
		tokens = decryptZoomTokens(envelopeOf(row));
	} catch (cryptoError) {
		if (cryptoError instanceof ZoomCryptoError) {
			await markNeedsReconnect(client);
			throw new ZoomError('Zoom needs to be connected again.', 'needs_reconnect');
		}
		throw cryptoError;
	}
	if (Date.parse(row.access_expires_at) - Date.now() > REFRESH_EARLY_MS) return tokens.accessToken;

	let reply: TokenReply;
	try {
		reply = await tokenRequest({ grant_type: 'refresh_token', refresh_token: tokens.refreshToken });
	} catch (refreshError) {
		if (refreshError instanceof ZoomError && refreshError.code === 'rejected') {
			// Another request may have refreshed already: use its token before giving up.
			const { data: latest } = await client
				.from('platform_zoom_connection')
				.select('*')
				.maybeSingle();
			if (latest && latest.credential_nonce !== row.credential_nonce) {
				const fresh = decryptZoomTokens(envelopeOf(latest));
				if (Date.parse(latest.access_expires_at) - Date.now() > REFRESH_EARLY_MS)
					return fresh.accessToken;
			}
			await markNeedsReconnect(client);
			throw new ZoomError('Zoom needs to be connected again.', 'needs_reconnect');
		}
		throw refreshError;
	}
	const saved = await client
		.from('platform_zoom_connection')
		.update({
			...envelopeColumns(
				encryptZoomTokens({ accessToken: reply.access_token, refreshToken: reply.refresh_token })
			),
			access_expires_at: new Date(Date.now() + reply.expires_in * 1000).toISOString()
		})
		.eq('id', true)
		.eq('credential_nonce', row.credential_nonce)
		.select('id');
	if (saved.error) throw saved.error;
	return reply.access_token;
}

async function zoomApi<T>(token: string, method: string, path: string, body?: unknown): Promise<T> {
	let response: Response;
	try {
		response = await fetch(`${apiBase()}${path}`, {
			method,
			headers: {
				Authorization: `Bearer ${token}`,
				...(body ? { 'Content-Type': 'application/json' } : {})
			},
			body: body ? JSON.stringify(body) : undefined,
			signal: AbortSignal.timeout(10_000)
		});
	} catch {
		throw new ZoomError('Zoom could not be reached.', 'unavailable');
	}
	if (response.status === 404 && method === 'DELETE') return undefined as T;
	if (response.status === 401)
		throw new ZoomError('Zoom needs to be connected again.', 'needs_reconnect');
	if (response.status === 429 || response.status >= 500)
		throw new ZoomError('Zoom is busy or having trouble.', 'unavailable');
	if (!response.ok)
		throw new ZoomError(`Zoom refused the request (${response.status}).`, 'rejected');
	if (response.status === 204) return undefined as T;
	return (await response.json()) as T;
}

/** Runs one Zoom call as Jafar; a refused token marks the connection as needing a fresh sign-in. */
async function asJafar<T>(client: Client, call: (token: string) => Promise<T>): Promise<T> {
	try {
		return await call(await accessToken(client));
	} catch (error) {
		if (error instanceof ZoomError && error.code === 'needs_reconnect')
			await markNeedsReconnect(client);
		throw error;
	}
}

export type ZoomMeetingInput = { topic: string; startsAt: string; endsAt: string };

const meetingBody = ({ topic, startsAt, endsAt }: ZoomMeetingInput) => ({
	topic: topic.slice(0, 200),
	type: 2,
	start_time: new Date(startsAt).toISOString().replace(/\.\d{3}Z$/, 'Z'),
	duration: Math.max(1, Math.round((Date.parse(endsAt) - Date.parse(startsAt)) / 60_000)),
	timezone: 'UTC'
});

/** A new scheduled meeting; the visitor gets `joinUrl`, never the host's start link. */
export function createZoomMeeting(client: Client, input: ZoomMeetingInput) {
	return asJafar(client, async (token) => {
		const made = await zoomApi<{ id: number | string; join_url: string }>(
			token,
			'POST',
			'/users/me/meetings',
			meetingBody(input)
		);
		return { meetingId: String(made.id), joinUrl: made.join_url };
	});
}

export const moveZoomMeeting = (client: Client, meetingId: string, input: ZoomMeetingInput) =>
	asJafar(client, (token) =>
		zoomApi<void>(token, 'PATCH', `/meetings/${encodeURIComponent(meetingId)}`, meetingBody(input))
	);

/** Deleting a meeting Zoom no longer has counts as done. */
export const deleteZoomMeeting = (client: Client, meetingId: string) =>
	asJafar(client, (token) =>
		zoomApi<void>(token, 'DELETE', `/meetings/${encodeURIComponent(meetingId)}`)
	);
