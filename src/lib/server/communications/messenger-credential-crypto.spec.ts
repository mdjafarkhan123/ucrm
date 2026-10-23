import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
	MessengerCredentialCryptoError,
	decryptMessengerSecret,
	encryptMessengerSecret,
	parseMessengerCredentialKeyring,
	type MessengerSecretContext
} from './messenger-credential-crypto';

const context: MessengerSecretContext = {
	organizationId: 'b2100000-0000-4000-8000-000000000001',
	recordId: 'b2200000-0000-4000-8000-000000000001',
	purpose: 'page_token'
};

const secret = `EAAB${'a'.repeat(180)}`;

function keyring(
	activeKeyId = 'v1',
	keys: Record<string, string> = { v1: randomBytes(32).toString('base64') }
) {
	return parseMessengerCredentialKeyring(JSON.stringify({ activeKeyId, keys }));
}

describe('Messenger credential encryption', () => {
	it('round-trips a secret and never stores it in the clear', () => {
		const ring = keyring();
		const encrypted = encryptMessengerSecret(secret, context, ring);

		expect(Buffer.from(encrypted.ciphertext).toString('utf8')).not.toContain('EAAB');
		expect(encrypted.nonce.byteLength).toBe(12);
		expect(encrypted.authenticationTag.byteLength).toBe(16);
		expect(decryptMessengerSecret(encrypted, context, ring)).toBe(secret);
	});

	it('uses a fresh nonce every time', () => {
		const ring = keyring();
		const first = encryptMessengerSecret(secret, context, ring);
		const second = encryptMessengerSecret(secret, context, ring);
		expect(Buffer.from(first.nonce).equals(Buffer.from(second.nonce))).toBe(false);
	});

	it.each([
		['another organization', { organizationId: 'b2100000-0000-4000-8000-000000000009' }],
		['another connection', { recordId: 'b2200000-0000-4000-8000-000000000009' }]
	])('refuses a ciphertext moved to %s', (_label, change) => {
		const ring = keyring();
		const encrypted = encryptMessengerSecret(secret, context, ring);
		expect(() => decryptMessengerSecret(encrypted, { ...context, ...change }, ring)).toThrow(
			MessengerCredentialCryptoError
		);
	});

	it('refuses a tampered ciphertext', () => {
		const ring = keyring();
		const encrypted = encryptMessengerSecret(secret, context, ring);
		encrypted.ciphertext[0] ^= 1;
		expect(() => decryptMessengerSecret(encrypted, context, ring)).toThrow(
			MessengerCredentialCryptoError
		);
	});

	it('still decrypts with a retired key after the active key rotates', () => {
		const oldKey = randomBytes(32).toString('base64');
		const encrypted = encryptMessengerSecret(secret, context, keyring('v1', { v1: oldKey }));
		const rotated = keyring('v2', { v1: oldKey, v2: randomBytes(32).toString('base64') });
		expect(decryptMessengerSecret(encrypted, context, rotated)).toBe(secret);
		expect(encryptMessengerSecret(secret, context, rotated).keyId).toBe('v2');
	});

	it.each([
		['missing', undefined],
		['not JSON', 'nope'],
		['a short key', JSON.stringify({ activeKeyId: 'v1', keys: { v1: 'c2hvcnQ=' } })],
		['an active key that is not in the ring', JSON.stringify({ activeKeyId: 'v2', keys: {} })]
	])('rejects a keyring that is %s', (_label, raw) => {
		expect(() => parseMessengerCredentialKeyring(raw)).toThrow(MessengerCredentialCryptoError);
	});
});
