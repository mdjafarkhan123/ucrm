import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
	messengerHandshakeChallenge,
	parseMessengerInboundMessages,
	readCappedBody,
	verifyMessengerSignature
} from './messenger-webhook';

const SECRET = 'app-secret';
const sign = (body: string, secret = SECRET) =>
	`sha256=${createHmac('sha256', secret).update(body).digest('hex')}`;
const bytes = (text: string) => new TextEncoder().encode(text);

describe('messengerHandshakeChallenge', () => {
	const params = (token: string, mode = 'subscribe') =>
		new URLSearchParams({
			'hub.mode': mode,
			'hub.verify_token': token,
			'hub.challenge': '1158201444'
		});

	it('echoes the challenge only for our verify token', () => {
		expect(messengerHandshakeChallenge(params('ours'), 'ours')).toBe('1158201444');
		expect(messengerHandshakeChallenge(params('theirs'), 'ours')).toBeNull();
		expect(messengerHandshakeChallenge(params('ours', 'unsubscribe'), 'ours')).toBeNull();
		expect(messengerHandshakeChallenge(params('ours'), undefined)).toBeNull();
	});
});

describe('verifyMessengerSignature', () => {
	const body = '{"object":"page","entry":[]}';

	it('accepts Meta’s signature over the exact bytes', () => {
		expect(verifyMessengerSignature(bytes(body), sign(body), SECRET)).toBe(true);
	});

	it('refuses a wrong secret, a changed body, a missing header or a malformed one', () => {
		expect(verifyMessengerSignature(bytes(body), sign(body, 'other'), SECRET)).toBe(false);
		expect(verifyMessengerSignature(bytes(body + ' '), sign(body), SECRET)).toBe(false);
		expect(verifyMessengerSignature(bytes(body), null, SECRET)).toBe(false);
		expect(verifyMessengerSignature(bytes(body), 'sha1=abc', SECRET)).toBe(false);
		expect(verifyMessengerSignature(bytes(body), sign(body), undefined)).toBe(false);
	});

	it('hashes escaped unicode as sent, never a re-serialized form', () => {
		const escaped = '{"text":"caf\\u00e9"}';
		expect(verifyMessengerSignature(bytes(escaped), sign(escaped), SECRET)).toBe(true);
		const reserialized = JSON.stringify(JSON.parse(escaped));
		expect(verifyMessengerSignature(bytes(reserialized), sign(escaped), SECRET)).toBe(false);
	});
});

describe('readCappedBody', () => {
	it('reads a body within the cap', async () => {
		const body = await readCappedBody(
			new Request('https://x', { method: 'POST', body: 'hello' }),
			10
		);
		expect(new TextDecoder().decode(body!)).toBe('hello');
	});

	it('refuses a body over the cap, declared or streamed', async () => {
		expect(
			await readCappedBody(new Request('https://x', { method: 'POST', body: 'x'.repeat(11) }), 10)
		).toBeNull();
		const declared = new Request('https://x', {
			method: 'POST',
			body: 'x',
			headers: { 'content-length': '5000' }
		});
		expect(await readCappedBody(declared, 10)).toBeNull();
	});
});

describe('parseMessengerInboundMessages', () => {
	const item = (overrides: Record<string, unknown> = {}) => ({
		sender: { id: '7001' },
		recipient: { id: '9001' },
		timestamp: 1_790_000_000_000,
		message: { mid: 'm_1', text: 'Can you quote my roof?' },
		...overrides
	});
	const delivery = (messaging: unknown[], pageId = '9001') => ({
		object: 'page',
		entry: [{ id: pageId, time: 1, messaging }]
	});

	it('reads a customer message with Meta’s time', () => {
		expect(parseMessengerInboundMessages(delivery([item()]))).toEqual([
			{
				pageId: '9001',
				psid: '7001',
				mid: 'm_1',
				text: 'Can you quote my roof?',
				attachmentCount: 0,
				sentAt: new Date(1_790_000_000_000).toISOString()
			}
		]);
	});

	it('counts attachments on a photo-only message', () => {
		const [message] = parseMessengerInboundMessages(
			delivery([
				item({ message: { mid: 'm_2', attachments: [{ type: 'image' }, { type: 'image' }] } })
			])
		);
		expect(message).toMatchObject({ text: '', attachmentCount: 2 });
	});

	it('reads every message in a batched delivery and skips what is not a customer message', () => {
		const messages = parseMessengerInboundMessages(
			delivery([
				item(),
				item({ message: { mid: 'm_echo', text: 'hi', is_echo: true } }),
				{ sender: { id: '7001' }, recipient: { id: '9001' }, delivery: { watermark: 1 } },
				{ sender: { id: '7001' }, recipient: { id: '9001' }, read: { watermark: 1 } },
				item({ sender: { id: 'not-a-number' } }),
				'garbage',
				item({ message: { mid: 'm_3', text: 'second' } })
			])
		);
		expect(messages.map((message) => message.mid)).toEqual(['m_1', 'm_3']);
	});

	it('ignores other objects, mismatched Pages and impossible timestamps', () => {
		expect(parseMessengerInboundMessages({ object: 'instagram', entry: [] })).toEqual([]);
		expect(parseMessengerInboundMessages(delivery([item()], '9002'))).toEqual([]);
		expect(parseMessengerInboundMessages(null)).toEqual([]);
		const [message] = parseMessengerInboundMessages(delivery([item({ timestamp: 1e20 })]));
		expect(message.sentAt).toBeNull();
	});
});
