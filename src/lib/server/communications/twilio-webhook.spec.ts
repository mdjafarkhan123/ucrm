import { createHmac } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: { APP_URL: 'https://app.example.com' } }));

import { env } from '$env/dynamic/private';
import {
	classifySmsConsentEvent,
	getTwilioInboundWebhookUrl,
	getTwilioStatusWebhookUrl,
	orderedValidationTokens,
	parseTwilioInboundParams,
	parseTwilioStatusParams,
	statusEventKey,
	validateTwilioSignature,
	type TwilioInboundParams
} from './twilio-webhook';

// Twilio's own signature algorithm: HMAC-SHA1 over the URL followed by each sorted key+value, base64.
function twilioSignature(token: string, url: string, params: Record<string, string>) {
	const data = Object.keys(params)
		.sort()
		.reduce((acc, key) => acc + key + params[key], url);
	return createHmac('sha1', token).update(Buffer.from(data, 'utf-8')).digest('base64');
}

const now = new Date('2026-09-15T12:00:00.000Z');
const future = '2026-09-15T13:00:00.000Z';
const past = '2026-09-15T11:00:00.000Z';

afterEach(() => {
	env.APP_URL = 'https://app.example.com';
});

describe('getTwilioStatusWebhookUrl', () => {
	it('builds the exact registered status path from APP_URL', () => {
		expect(getTwilioStatusWebhookUrl()).toBe('https://app.example.com/api/webhooks/twilio/status');
	});

	it('refuses a non-HTTPS origin outside local development', () => {
		env.APP_URL = 'http://app.example.com';
		expect(() => getTwilioStatusWebhookUrl()).toThrow();
	});

	it('allows localhost over http', () => {
		env.APP_URL = 'http://localhost:5173';
		expect(getTwilioStatusWebhookUrl()).toBe('http://localhost:5173/api/webhooks/twilio/status');
	});

	it('requires APP_URL to be set', () => {
		env.APP_URL = '';
		expect(() => getTwilioStatusWebhookUrl()).toThrow();
	});
});

describe('orderedValidationTokens', () => {
	it('orders current, staged, then prior', () => {
		const tokens = orderedValidationTokens(
			{
				current: { token: 'cur' },
				staged: { token: 'stg' },
				prior: { token: 'pri', retireAfter: future }
			},
			now
		);
		expect(tokens).toEqual(['cur', 'stg', 'pri']);
	});

	it('accepts the prior token only while its retire_after is in the future', () => {
		expect(
			orderedValidationTokens(
				{ current: { token: 'cur' }, prior: { token: 'pri', retireAfter: past } },
				now
			)
		).toEqual(['cur']);
	});

	it('drops a prior token that has no retirement window', () => {
		expect(
			orderedValidationTokens({ current: { token: 'cur' }, prior: { token: 'pri' } }, now)
		).toEqual(['cur']);
	});

	it('skips missing and empty tokens', () => {
		expect(
			orderedValidationTokens(
				{ current: null, staged: { token: '   ' }, prior: { token: 'pri', retireAfter: future } },
				now
			)
		).toEqual(['pri']);
	});
});

describe('validateTwilioSignature', () => {
	const url = 'https://app.example.com/api/webhooks/twilio/status';
	const params = {
		MessageSid: 'SM00000000000000000000000000000001',
		MessageStatus: 'delivered',
		AccountSid: 'AC00000000000000000000000000000001'
	};

	it('accepts a signature made with any listed token', () => {
		const signature = twilioSignature('staged-token', url, params);
		expect(validateTwilioSignature(['current-token', 'staged-token'], signature, url, params)).toBe(
			true
		);
	});

	it('accepts a signature made with a still-valid prior token', () => {
		const signature = twilioSignature('prior-token', url, params);
		expect(validateTwilioSignature(['current-token', 'prior-token'], signature, url, params)).toBe(
			true
		);
	});

	it('rejects a signature no listed token can produce', () => {
		const signature = twilioSignature('retired-token', url, params);
		expect(validateTwilioSignature(['current-token'], signature, url, params)).toBe(false);
	});

	it('rejects a missing signature and an empty token list', () => {
		const signature = twilioSignature('current-token', url, params);
		expect(validateTwilioSignature(['current-token'], null, url, params)).toBe(false);
		expect(validateTwilioSignature([], signature, url, params)).toBe(false);
	});
});

describe('parseTwilioStatusParams', () => {
	it('extracts the identifying fields from a valid status callback', () => {
		expect(
			parseTwilioStatusParams({
				MessageSid: 'SM00000000000000000000000000000001',
				MessageStatus: 'delivered',
				AccountSid: 'AC00000000000000000000000000000001',
				To: '+15005550006'
			})
		).toEqual({
			MessageSid: 'SM00000000000000000000000000000001',
			MessageStatus: 'delivered',
			AccountSid: 'AC00000000000000000000000000000001'
		});
	});

	it('rejects a malformed MessageSid or AccountSid', () => {
		expect(
			parseTwilioStatusParams({
				MessageSid: 'nope',
				MessageStatus: 'delivered',
				AccountSid: 'AC00000000000000000000000000000001'
			})
		).toBeNull();
		expect(
			parseTwilioStatusParams({
				MessageSid: 'SM00000000000000000000000000000001',
				MessageStatus: 'delivered',
				AccountSid: 'nope'
			})
		).toBeNull();
	});
});

describe('statusEventKey', () => {
	it('keys one row per message and status', () => {
		expect(
			statusEventKey({
				MessageSid: 'SM00000000000000000000000000000001',
				MessageStatus: 'delivered'
			})
		).toBe('SM00000000000000000000000000000001:delivered');
	});
});

describe('getTwilioInboundWebhookUrl', () => {
	it('builds the exact registered inbound path from APP_URL', () => {
		expect(getTwilioInboundWebhookUrl()).toBe(
			'https://app.example.com/api/webhooks/twilio/inbound'
		);
	});

	it('refuses a non-HTTPS origin outside local development', () => {
		env.APP_URL = 'http://app.example.com';
		expect(() => getTwilioInboundWebhookUrl()).toThrow();
	});
});

describe('parseTwilioInboundParams', () => {
	const base = {
		MessageSid: 'SM00000000000000000000000000000001',
		AccountSid: 'AC00000000000000000000000000000001',
		From: '+15005550006',
		To: '+15005550001',
		Body: 'Ahoy!',
		NumMedia: '2'
	};

	it('extracts and coerces the identifying fields', () => {
		expect(parseTwilioInboundParams(base)).toEqual({
			MessageSid: base.MessageSid,
			AccountSid: base.AccountSid,
			From: base.From,
			To: base.To,
			Body: 'Ahoy!',
			NumMedia: 2,
			OptOutType: undefined
		});
	});

	it('defaults an absent Body and NumMedia', () => {
		const { Body, NumMedia, ...rest } = base;
		expect(parseTwilioInboundParams(rest)).toMatchObject({ Body: '', NumMedia: 0 });
	});

	it('carries OptOutType when Advanced Opt-Out is configured', () => {
		expect(parseTwilioInboundParams({ ...base, OptOutType: 'STOP' })?.OptOutType).toBe('STOP');
	});

	it('rejects a malformed MessageSid or AccountSid', () => {
		expect(parseTwilioInboundParams({ ...base, MessageSid: 'nope' })).toBeNull();
		expect(parseTwilioInboundParams({ ...base, AccountSid: 'nope' })).toBeNull();
	});
});

describe('classifySmsConsentEvent', () => {
	function params(overrides: Partial<TwilioInboundParams>): TwilioInboundParams {
		return {
			MessageSid: 'SM00000000000000000000000000000001',
			AccountSid: 'AC00000000000000000000000000000001',
			From: '+15005550006',
			To: '+15005550001',
			Body: '',
			NumMedia: 0,
			...overrides
		};
	}

	it('prefers the provider-confirmed OptOutType over the body', () => {
		expect(classifySmsConsentEvent(params({ Body: 'something else', OptOutType: 'STOP' }))).toEqual(
			{
				kind: 'opt_out',
				confirmedByProvider: true
			}
		);
		expect(classifySmsConsentEvent(params({ OptOutType: 'START' }))).toEqual({
			kind: 'opt_in',
			confirmedByProvider: true
		});
		expect(classifySmsConsentEvent(params({ OptOutType: 'HELP' }))).toEqual({
			kind: 'help_requested',
			confirmedByProvider: true
		});
	});

	it('falls back to Twilio default keywords, case-insensitively, when OptOutType is absent', () => {
		expect(classifySmsConsentEvent(params({ Body: 'STOP' }))).toEqual({
			kind: 'opt_out',
			confirmedByProvider: false
		});
		expect(classifySmsConsentEvent(params({ Body: 'unsubscribe' }))).toEqual({
			kind: 'opt_out',
			confirmedByProvider: false
		});
		expect(classifySmsConsentEvent(params({ Body: '  Start ' }))).toEqual({
			kind: 'opt_in',
			confirmedByProvider: false
		});
		expect(classifySmsConsentEvent(params({ Body: 'Help' }))).toEqual({
			kind: 'help_requested',
			confirmedByProvider: false
		});
	});

	it('requires an exact keyword match, not a keyword within a longer message', () => {
		expect(classifySmsConsentEvent(params({ Body: 'please stop calling me' }))).toBeNull();
	});

	it('returns null for an ordinary reply', () => {
		expect(classifySmsConsentEvent(params({ Body: 'Sounds good, see you Tuesday!' }))).toBeNull();
	});
});
