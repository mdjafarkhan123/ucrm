import { createHmac } from 'node:crypto';
import { env } from '$env/dynamic/private';

// The few Meta Graph API calls connecting a Facebook Page needs (Facebook Login for Business, manual flow):
// code → user key → long-lived user key → the person's Pages with their Page keys → subscribe each Page to our
// webhook. Every call carries appsecret_proof, as Meta recommends for server calls, and gives up after 10 seconds
// so a slow Meta never holds a Settings request open.

const GRAPH_TIMEOUT_MS = 10_000;
const DEFAULT_GRAPH_VERSION = 'v25.0';
// The webhook fields Part 5 processes; Meta delivers nothing else to us.
export const MESSENGER_SUBSCRIBED_FIELDS = [
	'messages',
	'message_echoes',
	'message_deliveries',
	'message_reads',
	'messaging_policy_enforcement'
] as const;
// A Page key from someone with this Page task can read and send messages and change the subscription.
const MESSAGING_TASKS = new Set(['MESSAGING', 'MODERATE', 'MANAGE']);
const MAX_PAGE_LIST_REQUESTS = 5;

export type MessengerGraphFailure =
	'token_invalid' | 'permission_missing' | 'unavailable' | 'rejected';

export class MessengerGraphError extends Error {
	constructor(
		message: string,
		public readonly failure: MessengerGraphFailure,
		public readonly code: number | null = null
	) {
		super(message);
		this.name = 'MessengerGraphError';
	}
}

export type MessengerManagedPage = {
	id: string;
	name: string;
	category: string | null;
	followers: number | null;
	canMessage: boolean;
	accessToken: string | null;
};

type GraphConfig = { appId: string; appSecret: string; version: string; loginConfigId: string };

export function messengerGraphConfig(): GraphConfig | null {
	const appId = env.META_APP_ID?.trim();
	const appSecret = env.META_APP_SECRET?.trim();
	const loginConfigId = env.MESSENGER_LOGIN_CONFIG_ID?.trim();
	if (!appId || !appSecret || !loginConfigId) return null;
	const version = env.MESSENGER_GRAPH_VERSION?.trim();
	return {
		appId,
		appSecret,
		loginConfigId,
		version: version && /^v\d+\.\d+$/.test(version) ? version : DEFAULT_GRAPH_VERSION
	};
}

function requireConfig(): GraphConfig {
	const config = messengerGraphConfig();
	if (!config) throw new MessengerGraphError('Messenger is not configured.', 'unavailable');
	return config;
}

/** Facebook's login window for the "Messenger Page connect" configuration. */
export function messengerLoginDialogUrl(input: { state: string; redirectUri: string }): string {
	const config = requireConfig();
	const url = new URL(`https://www.facebook.com/${config.version}/dialog/oauth`);
	url.searchParams.set('client_id', config.appId);
	url.searchParams.set('redirect_uri', input.redirectUri);
	url.searchParams.set('state', input.state);
	url.searchParams.set('config_id', config.loginConfigId);
	url.searchParams.set('response_type', 'code');
	url.searchParams.set('override_default_response_type', 'true');
	return url.toString();
}

/** Meta's error envelope → what the business can do about it. Exported for tests. */
export function classifyGraphError(
	status: number,
	body: unknown
): { failure: MessengerGraphFailure; code: number | null; message: string } {
	const error =
		body && typeof body === 'object' && 'error' in body
			? (body as { error?: { code?: unknown; message?: unknown } }).error
			: undefined;
	const code = typeof error?.code === 'number' ? error.code : null;
	const message = typeof error?.message === 'string' ? error.message : `Graph HTTP ${status}`;
	if (code === 190 || code === 102) return { failure: 'token_invalid', code, message };
	if (code === 10 || code === 200 || (code !== null && code >= 200 && code < 300))
		return { failure: 'permission_missing', code, message };
	if (status >= 500 || code === 1 || code === 2 || code === 4 || code === 17 || code === 32)
		return { failure: 'unavailable', code, message };
	return { failure: 'rejected', code, message };
}

async function graphRequest<T>(
	method: 'GET' | 'POST' | 'DELETE',
	path: string,
	params: Record<string, string>,
	accessToken?: string
): Promise<T> {
	const config = requireConfig();
	const url = new URL(`https://graph.facebook.com/${config.version}/${path.replace(/^\//, '')}`);
	for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
	if (accessToken) {
		url.searchParams.set('access_token', accessToken);
		url.searchParams.set(
			'appsecret_proof',
			createHmac('sha256', config.appSecret).update(accessToken).digest('hex')
		);
	}

	let response: Response;
	try {
		response = await fetch(url, { method, signal: AbortSignal.timeout(GRAPH_TIMEOUT_MS) });
	} catch {
		throw new MessengerGraphError('Facebook could not be reached.', 'unavailable');
	}
	let body: unknown = null;
	try {
		body = await response.json();
	} catch {
		body = null;
	}
	if (!response.ok || (body && typeof body === 'object' && 'error' in body)) {
		const classified = classifyGraphError(response.status, body);
		throw new MessengerGraphError(classified.message, classified.failure, classified.code);
	}
	return body as T;
}

/** The code from Facebook's window → a long-lived user key (about 60 days; only used to list Pages). */
export async function exchangeMessengerLoginCode(
	code: string,
	redirectUri: string
): Promise<string> {
	const config = requireConfig();
	const short = await graphRequest<{ access_token?: string }>('GET', 'oauth/access_token', {
		client_id: config.appId,
		client_secret: config.appSecret,
		redirect_uri: redirectUri,
		code
	});
	if (!short.access_token) throw new MessengerGraphError('Facebook returned no key.', 'rejected');
	const long = await graphRequest<{ access_token?: string }>('GET', 'oauth/access_token', {
		grant_type: 'fb_exchange_token',
		client_id: config.appId,
		client_secret: config.appSecret,
		fb_exchange_token: short.access_token
	});
	return long.access_token ?? short.access_token;
}

export async function fetchMessengerFacebookUser(
	userToken: string
): Promise<{ id: string; name: string }> {
	const me = await graphRequest<{ id?: string; name?: string }>(
		'GET',
		'me',
		{ fields: 'id,name' },
		userToken
	);
	if (!me.id || !/^[0-9]{1,32}$/.test(me.id))
		throw new MessengerGraphError('Facebook returned no account.', 'rejected');
	return { id: me.id, name: me.name?.trim().slice(0, 200) || 'Facebook account' };
}

type RawPage = {
	id?: unknown;
	name?: unknown;
	category?: unknown;
	followers_count?: unknown;
	access_token?: unknown;
	tasks?: unknown;
};

/** One `/me/accounts` item → a Page we can show, or null when it is malformed. Exported for tests. */
export function parseManagedPage(raw: RawPage): MessengerManagedPage | null {
	if (typeof raw.id !== 'string' || !/^[0-9]{1,32}$/.test(raw.id)) return null;
	const name = typeof raw.name === 'string' ? raw.name.trim().slice(0, 200) : '';
	const tasks = Array.isArray(raw.tasks) ? raw.tasks.filter((t) => typeof t === 'string') : [];
	const accessToken =
		typeof raw.access_token === 'string' && raw.access_token ? raw.access_token : null;
	return {
		id: raw.id,
		name: name || 'Facebook Page',
		category: typeof raw.category === 'string' && raw.category ? raw.category : null,
		followers: typeof raw.followers_count === 'number' ? raw.followers_count : null,
		canMessage: Boolean(accessToken) && tasks.some((task) => MESSAGING_TASKS.has(task)),
		accessToken
	};
}

/** Every Page the person ticked in Facebook's window, with its Page key. */
export async function fetchMessengerManagedPages(
	userToken: string
): Promise<MessengerManagedPage[]> {
	const pages: MessengerManagedPage[] = [];
	let after: string | null = null;
	for (let request = 0; request < MAX_PAGE_LIST_REQUESTS; request++) {
		const params: Record<string, string> = {
			fields: 'id,name,category,followers_count,access_token,tasks',
			limit: '100'
		};
		if (after) params.after = after;
		const result = await graphRequest<{
			data?: RawPage[];
			paging?: { cursors?: { after?: string }; next?: string };
		}>('GET', 'me/accounts', params, userToken);
		for (const raw of result.data ?? []) {
			const page = parseManagedPage(raw);
			if (page) pages.push(page);
		}
		after = result.paging?.next ? (result.paging.cursors?.after ?? null) : null;
		if (!after) break;
	}
	return pages;
}

/** Ask Meta to deliver this Page's messages to our webhook. */
export async function subscribeMessengerPage(pageId: string, pageToken: string): Promise<void> {
	const result = await graphRequest<{ success?: boolean }>(
		'POST',
		`${pageId}/subscribed_apps`,
		{ subscribed_fields: MESSENGER_SUBSCRIBED_FIELDS.join(',') },
		pageToken
	);
	if (result.success !== true)
		throw new MessengerGraphError('Facebook did not subscribe the Page.', 'rejected');
}

/** Stop Meta delivering this Page's messages to us. */
export async function unsubscribeMessengerPage(pageId: string, pageToken: string): Promise<void> {
	await graphRequest<{ success?: boolean }>('DELETE', `${pageId}/subscribed_apps`, {}, pageToken);
}
