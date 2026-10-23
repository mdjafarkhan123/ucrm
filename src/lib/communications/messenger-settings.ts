import { httpError } from '$lib/http-error';

// Settings → Messenger: the business's connected Facebook Pages (concept.pen board `tEAXY`, Approved B). Shared by
// the page and its API so both speak the same shapes. No Facebook key ever reaches the browser.

export type MessengerReconnectReason =
	'token_invalid' | 'permission_missing' | 'webhook_unsubscribed';

export type MessengerPageStatus = 'receiving' | 'waiting' | 'reconnect';

export type MessengerConnection = {
	id: string;
	page_id: string;
	page_name: string;
	status: MessengerPageStatus;
	reason: MessengerReconnectReason | null;
	/** When the Page stopped working, for the reason strip ("Facebook ended this connection on Oct 20"). */
	problem_at: string | null;
	is_default: boolean;
	connected_by_name: string | null;
	connected_at: string;
	last_message: { at: string; client_name: string } | null;
};

export type MessengerOverview = {
	/** False until Uplift has set Meta's app keys on the server. */
	configured: boolean;
	facebook_user_name: string | null;
	new_conversations_this_week: number;
	connections: MessengerConnection[];
};

/** A Page offered in the Choose Pages pop-up after Facebook's window closes. */
export type MessengerPageChoice = {
	id: string;
	name: string;
	category: string | null;
	followers: number | null;
	/** available: can be ticked. connected: already on this business. reconnect: on this business but
	 *  needs a fresh key, so it can be ticked. elsewhere: another business on Uplift has it. no_permission: the
	 *  person is not allowed to manage the Page's messages. */
	state: 'available' | 'connected' | 'reconnect' | 'elsewhere' | 'no_permission';
};

export type MessengerPageChoices = {
	session_id: string;
	facebook_user_name: string;
	pages: MessengerPageChoice[];
};

export type MessengerConnectResult = {
	connected: { id: string; page_id: string; page_name: string }[];
	failed: { page_id: string; page_name: string; message: string }[];
};

export type MessengerTestArrival = {
	arrived: { at: string; client_id: string; client_name: string; new_lead: boolean } | null;
};

/** What Facebook's window posts back to the Settings page when it closes. */
export type MessengerLoginOutcome =
	| { type: 'ucrm-messenger-login'; result: 'ok'; session_id: string }
	| { type: 'ucrm-messenger-login'; result: 'cancelled' | 'no_pages' | 'failed' };

export const messengerOverviewKey = ['settings', 'communications', 'messenger'] as const;

export const messengerTestKey = (connectionId: string, since: string) =>
	['settings', 'communications', 'messenger', 'test', connectionId, since] as const;

export const MESSENGER_SETTINGS_API = '/api/settings/communications/messenger';

async function readJson<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const body = await response.json().catch(() => null);
		throw httpError(response, body?.error ?? fallback);
	}
	return response.json() as Promise<T>;
}

export async function fetchMessengerOverview(): Promise<MessengerOverview> {
	return readJson(await fetch(MESSENGER_SETTINGS_API), 'Your Facebook Pages could not be loaded.');
}

export async function fetchMessengerPageChoices(sessionId: string): Promise<MessengerPageChoices> {
	return readJson(
		await fetch(`${MESSENGER_SETTINGS_API}/pages?session=${encodeURIComponent(sessionId)}`),
		'Your Facebook Pages could not be loaded.'
	);
}

export async function connectMessengerPages(
	sessionId: string,
	pageIds: string[]
): Promise<MessengerConnectResult> {
	return readJson(
		await fetch(`${MESSENGER_SETTINGS_API}/connections`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ session_id: sessionId, page_ids: pageIds })
		}),
		'The Pages could not be connected. Nothing was changed.'
	);
}

export async function makeMessengerPageDefault(connectionId: string): Promise<void> {
	await readJson(
		await fetch(`${MESSENGER_SETTINGS_API}/connections/${connectionId}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ is_default: true })
		}),
		'The default Page could not be changed.'
	);
}

export async function disconnectMessengerPage(connectionId: string): Promise<void> {
	await readJson(
		await fetch(`${MESSENGER_SETTINGS_API}/connections/${connectionId}`, { method: 'DELETE' }),
		'The Page could not be disconnected.'
	);
}

export async function fetchMessengerTestArrival(
	connectionId: string,
	since: string
): Promise<MessengerTestArrival> {
	return readJson(
		await fetch(
			`${MESSENGER_SETTINGS_API}/connections/${connectionId}/test?since=${encodeURIComponent(since)}`
		),
		'The live test could not check for your message.'
	);
}
