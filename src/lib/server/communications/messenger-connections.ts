import { randomUUID } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	decryptMessengerSecret,
	encryptMessengerSecret,
	type EncryptedMessengerSecret
} from './messenger-credential-crypto';
import {
	MessengerGraphError,
	fetchMessengerManagedPages,
	messengerGraphConfig,
	subscribeMessengerPage,
	unsubscribeMessengerPage,
	type MessengerManagedPage
} from './messenger-graph';
import type {
	MessengerConnectResult,
	MessengerConnection,
	MessengerOverview,
	MessengerPageChoice,
	MessengerPageChoices,
	MessengerReconnectReason,
	MessengerTestArrival
} from '$lib/communications/messenger-settings';

// Connecting and disconnecting a business's Facebook Pages (Messenger Part 4). Tables are server-only (RLS on, no
// policies), so every read and write here runs on the owner client after the route has checked the member's
// permission and passes their organization. Reconnecting a Page this business had before revives its row, so old
// conversations stay and the same threads continue (Jafar, 2026-10-23).

const CONNECTION_COLUMNS =
	'id, organization_id, page_id, page_name, status, needs_reconnect_reason, is_default, encryption_key_id, page_token_nonce, page_token_ciphertext, page_token_tag, connected_by, connected_at, updated_at, last_event_received_at, facebook_user_name';

type ConnectionRow = {
	id: string;
	organization_id: string;
	page_id: string;
	page_name: string;
	status: string;
	needs_reconnect_reason: string | null;
	is_default: boolean;
	encryption_key_id: string | null;
	page_token_nonce: string | null;
	page_token_ciphertext: string | null;
	page_token_tag: string | null;
	connected_by: string | null;
	connected_at: string;
	updated_at: string;
	last_event_received_at: string | null;
	facebook_user_name: string | null;
};

function toHex(bytes: Uint8Array) {
	return `\\x${Buffer.from(bytes).toString('hex')}`;
}

function fromHex(value: string): Uint8Array {
	const hex = value.startsWith('\\x') ? value.slice(2) : value;
	return new Uint8Array(Buffer.from(hex, 'hex'));
}

function sealed(secret: EncryptedMessengerSecret) {
	return {
		keyId: secret.keyId,
		nonce: toHex(secret.nonce),
		ciphertext: toHex(secret.ciphertext),
		tag: toHex(secret.authenticationTag)
	};
}

function pageTokenOf(row: ConnectionRow): string | null {
	if (
		!row.encryption_key_id ||
		!row.page_token_nonce ||
		!row.page_token_ciphertext ||
		!row.page_token_tag
	)
		return null;
	return decryptMessengerSecret(
		{
			keyId: row.encryption_key_id,
			nonce: fromHex(row.page_token_nonce),
			ciphertext: fromHex(row.page_token_ciphertext),
			authenticationTag: fromHex(row.page_token_tag)
		},
		{ organizationId: row.organization_id, recordId: row.id, purpose: 'page_token' }
	);
}

/** A stored row → what the Settings card shows. Exported for tests. */
export function messengerConnectionView(
	row: Pick<
		ConnectionRow,
		| 'id'
		| 'page_id'
		| 'page_name'
		| 'status'
		| 'needs_reconnect_reason'
		| 'is_default'
		| 'connected_at'
		| 'updated_at'
		| 'last_event_received_at'
	>,
	extras: {
		connectedByName: string | null;
		lastMessage: MessengerConnection['last_message'];
	}
): MessengerConnection {
	const needsReconnect = row.status === 'needs_reconnect';
	return {
		id: row.id,
		page_id: row.page_id,
		page_name: row.page_name,
		status: needsReconnect
			? 'reconnect'
			: row.last_event_received_at || extras.lastMessage
				? 'receiving'
				: 'waiting',
		reason: needsReconnect
			? ((row.needs_reconnect_reason as MessengerReconnectReason | null) ?? 'token_invalid')
			: null,
		problem_at: needsReconnect ? row.updated_at : null,
		is_default: row.is_default,
		connected_by_name: extras.connectedByName,
		connected_at: row.connected_at,
		last_message: extras.lastMessage
	};
}

export async function loadMessengerOverview(organizationId: string): Promise<MessengerOverview> {
	const owner = getOwnerSupabaseClient();
	const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
	const [connections, newThisWeek] = await Promise.all([
		owner
			.from('communication_messenger_connections')
			.select(CONNECTION_COLUMNS)
			.eq('organization_id', organizationId)
			.neq('status', 'disconnected')
			.order('connected_at'),
		owner
			.from('communication_messenger_identities')
			.select('id', { count: 'exact', head: true })
			.eq('organization_id', organizationId)
			.gte('created_at', weekAgo)
	]);
	if (connections.error) throw connections.error;
	if (newThisWeek.error) throw newThisWeek.error;
	const rows = (connections.data ?? []) as ConnectionRow[];

	const lastMessages = new Map<string, { at: string; clientId: string }>();
	const names = new Map<string, string>();
	if (rows.length) {
		const identities = await owner
			.from('communication_messenger_identities')
			.select('connection_id, client_id, last_inbound_at')
			.eq('organization_id', organizationId)
			.in(
				'connection_id',
				rows.map((row) => row.id)
			)
			.not('last_inbound_at', 'is', null)
			.order('last_inbound_at', { ascending: false })
			.limit(200);
		if (identities.error) throw identities.error;
		for (const identity of identities.data ?? []) {
			if (!lastMessages.has(identity.connection_id) && identity.last_inbound_at)
				lastMessages.set(identity.connection_id, {
					at: identity.last_inbound_at,
					clientId: identity.client_id
				});
		}

		const clientIds = [...new Set([...lastMessages.values()].map((entry) => entry.clientId))];
		const userIds = [
			...new Set(rows.map((row) => row.connected_by).filter((id): id is string => Boolean(id)))
		];
		const [clients, profiles] = await Promise.all([
			clientIds.length
				? owner
						.from('clients')
						.select('id, display_name')
						.eq('organization_id', organizationId)
						.in('id', clientIds)
				: Promise.resolve({ data: [], error: null }),
			userIds.length
				? owner.from('profiles').select('id, full_name').in('id', userIds)
				: Promise.resolve({ data: [], error: null })
		]);
		if (clients.error) throw clients.error;
		if (profiles.error) throw profiles.error;
		for (const client of clients.data ?? []) names.set(`client:${client.id}`, client.display_name);
		for (const profile of profiles.data ?? [])
			if (profile.full_name) names.set(`user:${profile.id}`, profile.full_name);
	}

	const latestLogin = [...rows]
		.filter((row) => row.facebook_user_name)
		.sort((a, b) => b.connected_at.localeCompare(a.connected_at))[0];

	return {
		configured: messengerGraphConfig() !== null,
		facebook_user_name: latestLogin?.facebook_user_name ?? null,
		new_conversations_this_week: newThisWeek.count ?? 0,
		connections: rows.map((row) => {
			const last = lastMessages.get(row.id);
			return messengerConnectionView(row, {
				connectedByName: row.connected_by ? (names.get(`user:${row.connected_by}`) ?? null) : null,
				lastMessage: last
					? { at: last.at, client_name: names.get(`client:${last.clientId}`) ?? 'Facebook user' }
					: null
			});
		})
	};
}

// Login sessions -----------------------------------------------------------------------------------------------

export async function saveMessengerLoginSession(input: {
	organizationId: string;
	userId: string;
	userToken: string;
	facebookUser: { id: string; name: string };
}): Promise<string> {
	const owner = getOwnerSupabaseClient();
	// One live login per member; anything expired anywhere goes too.
	const cleanup = await owner
		.from('communication_messenger_login_sessions')
		.delete()
		.or(
			`expires_at.lt.${new Date().toISOString()},and(organization_id.eq.${input.organizationId},user_id.eq.${input.userId})`
		);
	if (cleanup.error) throw cleanup.error;

	const id = randomUUID();
	const secret = sealed(
		encryptMessengerSecret(input.userToken, {
			organizationId: input.organizationId,
			recordId: id,
			purpose: 'login_user_token'
		})
	);
	const { error } = await owner.from('communication_messenger_login_sessions').insert({
		id,
		organization_id: input.organizationId,
		user_id: input.userId,
		facebook_user_id: input.facebookUser.id,
		facebook_user_name: input.facebookUser.name,
		encryption_key_id: secret.keyId,
		user_token_nonce: secret.nonce,
		user_token_ciphertext: secret.ciphertext,
		user_token_tag: secret.tag
	});
	if (error) throw error;
	return id;
}

async function openLoginSession(organizationId: string, userId: string, sessionId: string) {
	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_messenger_login_sessions')
		.select(
			'id, facebook_user_name, encryption_key_id, user_token_nonce, user_token_ciphertext, user_token_tag, expires_at'
		)
		.eq('id', sessionId)
		.eq('organization_id', organizationId)
		.eq('user_id', userId)
		.maybeSingle();
	if (error) throw error;
	if (!data || new Date(data.expires_at).getTime() <= Date.now()) return null;
	return {
		facebookUserName: data.facebook_user_name,
		userToken: decryptMessengerSecret(
			{
				keyId: data.encryption_key_id,
				nonce: fromHex(data.user_token_nonce),
				ciphertext: fromHex(data.user_token_ciphertext),
				authenticationTag: fromHex(data.user_token_tag)
			},
			{ organizationId, recordId: sessionId, purpose: 'login_user_token' }
		)
	};
}

/** How each managed Page relates to this business and to others. Exported for tests. */
export function messengerPageChoiceState(
	page: Pick<MessengerManagedPage, 'id' | 'canMessage'>,
	ours: Map<string, string>,
	livePagesElsewhere: Set<string>
): MessengerPageChoice['state'] {
	const status = ours.get(page.id);
	if (status === 'active') return 'connected';
	if (livePagesElsewhere.has(page.id)) return 'elsewhere';
	if (!page.canMessage) return 'no_permission';
	return status === 'needs_reconnect' ? 'reconnect' : 'available';
}

async function pageRelations(organizationId: string, pageIds: string[]) {
	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_messenger_connections')
		.select('organization_id, page_id, status')
		.in('page_id', pageIds.length ? pageIds : ['0']);
	if (error) throw error;
	const ours = new Map<string, string>();
	const elsewhere = new Set<string>();
	for (const row of data ?? []) {
		if (row.organization_id === organizationId) ours.set(row.page_id, row.status);
		else if (row.status !== 'disconnected') elsewhere.add(row.page_id);
	}
	return { ours, elsewhere };
}

export type MessengerSessionFailure =
	'session_expired' | 'facebook_unavailable' | 'facebook_refused';

function sessionFailure(error: unknown): MessengerSessionFailure {
	if (error instanceof MessengerGraphError)
		return error.failure === 'unavailable' ? 'facebook_unavailable' : 'facebook_refused';
	throw error;
}

export async function listMessengerPageChoices(input: {
	organizationId: string;
	userId: string;
	sessionId: string;
}): Promise<
	{ ok: true; choices: MessengerPageChoices } | { ok: false; reason: MessengerSessionFailure }
> {
	const session = await openLoginSession(input.organizationId, input.userId, input.sessionId);
	if (!session) return { ok: false, reason: 'session_expired' };
	let pages: MessengerManagedPage[];
	try {
		pages = await fetchMessengerManagedPages(session.userToken);
	} catch (error) {
		return { ok: false, reason: sessionFailure(error) };
	}
	const { ours, elsewhere } = await pageRelations(
		input.organizationId,
		pages.map((page) => page.id)
	);
	return {
		ok: true,
		choices: {
			session_id: input.sessionId,
			facebook_user_name: session.facebookUserName,
			pages: pages.map((page) => ({
				id: page.id,
				name: page.name,
				category: page.category,
				followers: page.followers,
				state: messengerPageChoiceState(page, ours, elsewhere)
			}))
		}
	};
}

const CONNECT_FAILURE_MESSAGES = {
	not_shared: "Facebook didn't share this Page with us. Log in again and leave it ticked.",
	no_permission: "Your Facebook account can't manage this Page's messages. Ask a Page admin.",
	elsewhere: 'Another business on Uplift already has this Page connected.',
	connected: 'This Page is already connected.',
	facebook_refused: 'Facebook refused to connect this Page. Try again in a minute.',
	facebook_unavailable: 'Facebook could not be reached. Try again in a minute.'
} as const;

export async function connectMessengerPages(input: {
	organizationId: string;
	userId: string;
	sessionId: string;
	pageIds: string[];
}): Promise<
	{ ok: true; result: MessengerConnectResult } | { ok: false; reason: MessengerSessionFailure }
> {
	const owner = getOwnerSupabaseClient();
	const session = await openLoginSession(input.organizationId, input.userId, input.sessionId);
	if (!session) return { ok: false, reason: 'session_expired' };
	let pages: MessengerManagedPage[];
	try {
		pages = await fetchMessengerManagedPages(session.userToken);
	} catch (error) {
		return { ok: false, reason: sessionFailure(error) };
	}

	const byId = new Map(pages.map((page) => [page.id, page]));
	const { ours, elsewhere } = await pageRelations(input.organizationId, input.pageIds);
	const existing = await owner
		.from('communication_messenger_connections')
		.select('id, page_id, is_default, status')
		.eq('organization_id', input.organizationId);
	if (existing.error) throw existing.error;
	const rowsByPage = new Map((existing.data ?? []).map((row) => [row.page_id, row]));

	const result: MessengerConnectResult = { connected: [], failed: [] };
	const fail = (pageId: string, name: string, reason: keyof typeof CONNECT_FAILURE_MESSAGES) =>
		result.failed.push({
			page_id: pageId,
			page_name: name,
			message: CONNECT_FAILURE_MESSAGES[reason]
		});

	for (const pageId of input.pageIds) {
		const page = byId.get(pageId);
		if (!page) {
			fail(pageId, 'Facebook Page', 'not_shared');
			continue;
		}
		const state = messengerPageChoiceState(page, ours, elsewhere);
		if (state !== 'available' && state !== 'reconnect') {
			fail(page.id, page.name, state);
			continue;
		}

		try {
			await subscribeMessengerPage(page.id, page.accessToken!);
		} catch (error) {
			if (!(error instanceof MessengerGraphError)) throw error;
			fail(
				page.id,
				page.name,
				error.failure === 'unavailable'
					? 'facebook_unavailable'
					: error.failure === 'permission_missing'
						? 'no_permission'
						: 'facebook_refused'
			);
			continue;
		}

		const previous = rowsByPage.get(page.id);
		const id = previous?.id ?? randomUUID();
		const secret = sealed(
			encryptMessengerSecret(page.accessToken!, {
				organizationId: input.organizationId,
				recordId: id,
				purpose: 'page_token'
			})
		);
		const now = new Date().toISOString();
		const values = {
			page_name: page.name,
			status: 'active',
			needs_reconnect_reason: null,
			encryption_key_id: secret.keyId,
			page_token_nonce: secret.nonce,
			page_token_ciphertext: secret.ciphertext,
			page_token_tag: secret.tag,
			connected_by: input.userId,
			facebook_user_name: session.facebookUserName,
			disconnected_at: null,
			last_checked_at: now,
			updated_at: now
		};
		// A reconnect keeps its first connection date; a revived (disconnected) Page starts a fresh one.
		const saved = previous
			? await owner
					.from('communication_messenger_connections')
					.update(previous.status === 'disconnected' ? { ...values, connected_at: now } : values)
					.eq('id', previous.id)
					.eq('organization_id', input.organizationId)
			: await owner.from('communication_messenger_connections').insert({
					...values,
					id,
					organization_id: input.organizationId,
					page_id: page.id,
					connected_at: now
				});
		if (saved.error) {
			// The live-Page key: another business connected it in the meantime.
			if (saved.error.code === '23505') {
				fail(page.id, page.name, 'elsewhere');
				continue;
			}
			throw saved.error;
		}
		result.connected.push({ id, page_id: page.id, page_name: page.name });
	}

	if (result.connected.length) await ensureDefault(input.organizationId);
	if (!result.failed.length)
		await owner.from('communication_messenger_login_sessions').delete().eq('id', input.sessionId);
	return { ok: true, result };
}

/** A business with any live Page always has a default one: the earliest connected. */
async function ensureDefault(organizationId: string) {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('communication_messenger_connections')
		.select('id, is_default')
		.eq('organization_id', organizationId)
		.neq('status', 'disconnected')
		.order('connected_at');
	if (error) throw error;
	if (!data?.length || data.some((row) => row.is_default)) return;
	const { error: updateError } = await owner
		.from('communication_messenger_connections')
		.update({ is_default: true, updated_at: new Date().toISOString() })
		.eq('id', data[0].id);
	// Another request set a default first: that one stands.
	if (updateError && updateError.code !== '23505') throw updateError;
}

async function loadLiveConnection(organizationId: string, connectionId: string) {
	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_messenger_connections')
		.select(CONNECTION_COLUMNS)
		.eq('organization_id', organizationId)
		.eq('id', connectionId)
		.neq('status', 'disconnected')
		.maybeSingle();
	if (error) throw error;
	return (data as ConnectionRow | null) ?? null;
}

export async function makeMessengerPageDefault(
	organizationId: string,
	connectionId: string
): Promise<boolean> {
	const row = await loadLiveConnection(organizationId, connectionId);
	if (!row) return false;
	if (row.is_default) return true;
	const owner = getOwnerSupabaseClient();
	const now = new Date().toISOString();
	const cleared = await owner
		.from('communication_messenger_connections')
		.update({ is_default: false, updated_at: now })
		.eq('organization_id', organizationId)
		.eq('is_default', true);
	if (cleared.error) throw cleared.error;
	const set = await owner
		.from('communication_messenger_connections')
		.update({ is_default: true, updated_at: now })
		.eq('id', row.id);
	if (set.error) throw set.error;
	return true;
}

/** Stops new messages from the Page and wipes its key; conversations and threads stay. */
export async function disconnectMessengerPage(
	organizationId: string,
	connectionId: string
): Promise<boolean> {
	const row = await loadLiveConnection(organizationId, connectionId);
	if (!row) return false;

	// Best effort: a Page whose key Facebook already ended has no subscription left to remove.
	try {
		const token = pageTokenOf(row);
		if (token) await unsubscribeMessengerPage(row.page_id, token);
	} catch (error) {
		console.warn('Messenger unsubscribe failed during disconnect; disconnecting anyway.', {
			connectionId,
			failure: error instanceof MessengerGraphError ? error.failure : 'decrypt'
		});
	}

	const now = new Date().toISOString();
	const { error } = await getOwnerSupabaseClient()
		.from('communication_messenger_connections')
		.update({
			status: 'disconnected',
			needs_reconnect_reason: null,
			is_default: false,
			encryption_key_id: null,
			page_token_nonce: null,
			page_token_ciphertext: null,
			page_token_tag: null,
			disconnected_at: now,
			updated_at: now
		})
		.eq('id', row.id)
		.eq('organization_id', organizationId);
	if (error) throw error;
	if (row.is_default) await ensureDefault(organizationId);
	return true;
}

/** The first message to reach this Page since the live test began. */
export async function findMessengerTestArrival(
	organizationId: string,
	connectionId: string,
	since: string
): Promise<MessengerTestArrival | null> {
	const owner = getOwnerSupabaseClient();
	const row = await loadLiveConnection(organizationId, connectionId);
	if (!row) return null;
	const { data, error } = await owner
		.from('communication_messenger_identities')
		.select('client_id, last_inbound_at')
		.eq('organization_id', organizationId)
		.eq('connection_id', connectionId)
		.gte('last_inbound_at', since)
		.order('last_inbound_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (error) throw error;
	if (!data?.last_inbound_at) return { arrived: null };
	const client = await owner
		.from('clients')
		.select('display_name, created_at')
		.eq('organization_id', organizationId)
		.eq('id', data.client_id)
		.maybeSingle();
	if (client.error) throw client.error;
	return {
		arrived: {
			at: data.last_inbound_at,
			client_id: data.client_id,
			client_name: client.data?.display_name ?? 'Facebook user',
			new_lead: client.data
				? new Date(client.data.created_at).getTime() >= new Date(since).getTime()
				: false
		}
	};
}

/** The Page key a reply is sent with, decrypted just before the send; null when the Page holds no key. */
export async function loadMessengerPageToken(input: {
	organizationId: string;
	connectionId: string;
}): Promise<string | null> {
	const row = await loadLiveConnection(input.organizationId, input.connectionId);
	return row ? pageTokenOf(row) : null;
}
