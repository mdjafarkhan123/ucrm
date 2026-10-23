import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({
	env: {
		META_APP_ID: '1709471683925717',
		META_APP_SECRET: 'secret',
		MESSENGER_LOGIN_CONFIG_ID: '1133535439212464',
		MESSENGER_GRAPH_VERSION: 'v25.0'
	}
}));

const { classifyGraphError, messengerLoginDialogUrl, parseManagedPage } =
	await import('./messenger-graph');

afterEach(() => vi.unstubAllGlobals());

describe('checkMessengerPageHealth', () => {
	const appId = '1709471683925717';
	const valid = {
		is_valid: true,
		app_id: appId,
		scopes: ['pages_messaging', 'pages_manage_metadata'],
		expires_at: 0,
		data_access_expires_at: 0
	};
	const fields = [
		'messages',
		'message_echoes',
		'message_deliveries',
		'message_reads',
		'messaging_policy_enforcement'
	];
	async function check(
		token: unknown = valid,
		subscriptions: unknown = [{ id: appId, subscribed_fields: fields }]
	) {
		const fetcher = vi
			.fn()
			.mockResolvedValueOnce(Response.json({ data: token }))
			.mockResolvedValueOnce(Response.json({ data: subscriptions }));
		vi.stubGlobal('fetch', fetcher);
		const { checkMessengerPageHealth } = await import('./messenger-graph');
		return { outcome: await checkMessengerPageHealth('42', 'private-page-token'), fetcher };
	}

	it('checks the token and this app subscription without sending or modifying anything', async () => {
		const { outcome, fetcher } = await check();
		expect(outcome).toBe('healthy');
		expect(fetcher).toHaveBeenCalledTimes(2);
		expect(fetcher.mock.calls.every(([, options]) => options.method === 'GET')).toBe(true);
		expect(new URL(fetcher.mock.calls[1][0]).pathname).toBe('/v25.0/42/subscribed_apps');
	});
	it.each([
		{ ...valid, is_valid: false },
		{ ...valid, app_id: 'other-app' },
		{ ...valid, expires_at: 1 },
		{ ...valid, data_access_expires_at: 1 }
	])('detects an unusable token before reading subscriptions: %j', async (token) => {
		const { outcome, fetcher } = await check(token);
		expect(outcome).toBe('token_invalid');
		expect(fetcher).toHaveBeenCalledOnce();
	});
	it('detects a revoked messaging permission even if metadata permission remains', async () => {
		expect((await check({ ...valid, scopes: ['pages_manage_metadata'] })).outcome).toBe(
			'permission_missing'
		);
	});
	it.each([
		{ subscriptions: [] },
		{ subscriptions: [{ id: 'another-app', subscribed_fields: fields }] },
		{ subscriptions: [{ id: appId, subscribed_fields: ['messages'] }] }
	])('detects missing subscription or fields: %j', async ({ subscriptions }) => {
		expect((await check(valid, subscriptions)).outcome).toBe('webhook_unsubscribed');
	});
	it.each([null, {}, { ...valid, scopes: null }])(
		'defers malformed token responses: %j',
		async (token) => {
			await expect(check(token)).rejects.toThrow();
		}
	);
	it('defers a broken subscription response', async () => {
		await expect(check(valid, null)).rejects.toThrow();
	});
	it.each([
		[190, 'token_invalid'],
		[200, 'permission_missing']
	])('classifies a Page refusal %s', async (code, outcome) => {
		vi.stubGlobal(
			'fetch',
			vi
				.fn()
				.mockResolvedValueOnce(Response.json({ data: valid }))
				.mockResolvedValueOnce(Response.json({ error: { code } }, { status: 400 }))
		);
		const { checkMessengerPageHealth } = await import('./messenger-graph');
		await expect(checkMessengerPageHealth('42', 'key')).resolves.toBe(outcome);
	});
	it('defers inspecting app credential errors instead of blaming the Page', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn().mockResolvedValue(Response.json({ error: { code: 190 } }, { status: 400 }))
		);
		const { checkMessengerPageHealth } = await import('./messenger-graph');
		await expect(checkMessengerPageHealth('42', 'key')).rejects.toThrow();
	});
});

describe('messengerLoginDialogUrl', () => {
	it('opens the Messenger Page connect configuration and asks for a code', () => {
		const url = new URL(
			messengerLoginDialogUrl({
				state: 'abc',
				redirectUri: 'https://app.example.com/api/settings/communications/messenger/callback'
			})
		);
		expect(url.origin + url.pathname).toBe('https://www.facebook.com/v25.0/dialog/oauth');
		expect(Object.fromEntries(url.searchParams)).toEqual({
			client_id: '1709471683925717',
			redirect_uri: 'https://app.example.com/api/settings/communications/messenger/callback',
			state: 'abc',
			config_id: '1133535439212464',
			response_type: 'code',
			override_default_response_type: 'true'
		});
	});
});

describe('classifyGraphError', () => {
	it.each([
		[400, { error: { code: 190, message: 'Invalid OAuth access token' } }, 'token_invalid'],
		[403, { error: { code: 10, message: 'Permission denied' } }, 'permission_missing'],
		[403, { error: { code: 230, message: 'Requires pages_messaging' } }, 'permission_missing'],
		[400, { error: { code: 4, message: 'Too many calls' } }, 'unavailable'],
		[400, { error: { code: 10, error_subcode: 2018278, message: 'Outside window' } }, 'rejected'],
		[503, null, 'unavailable'],
		[400, { error: { code: 100, message: 'Invalid parameter' } }, 'rejected']
	])('HTTP %i %j → %s', (status, body, failure) => {
		expect(classifyGraphError(status, body).failure).toBe(failure);
	});
});

describe('parseManagedPage', () => {
	it('keeps a Page whose key can manage messages', () => {
		expect(
			parseManagedPage({
				id: '1121199934412688',
				name: ' Uplift Contractor ',
				category: 'Contractor',
				followers_count: 12,
				access_token: 'page-key',
				tasks: ['ADVERTISE', 'MESSAGING']
			})
		).toEqual({
			id: '1121199934412688',
			name: 'Uplift Contractor',
			category: 'Contractor',
			followers: 12,
			canMessage: true,
			accessToken: 'page-key'
		});
	});

	it('marks a Page the person cannot message from', () => {
		expect(
			parseManagedPage({ id: '42', name: 'Ads only', access_token: 'k', tasks: ['ADVERTISE'] })
				?.canMessage
		).toBe(false);
		expect(parseManagedPage({ id: '42', name: 'No key', tasks: ['MESSAGING'] })?.canMessage).toBe(
			false
		);
	});

	it('drops malformed items', () => {
		expect(parseManagedPage({ id: 'not-a-number', name: 'x' })).toBeNull();
		expect(parseManagedPage({ name: 'x' })).toBeNull();
	});
});
