import { describe, expect, it, vi } from 'vitest';

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
