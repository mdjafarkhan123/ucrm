import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
	StripeCredentialCryptoError,
	decryptStripeSecret,
	encryptStripeSecret,
	parseStripeCredentialKeyring,
	type StripeSecretContext
} from './stripe-credential-crypto';

const context: StripeSecretContext = {
	organizationId: 'b2100000-0000-4000-8000-000000000001',
	connectionId: 'b2200000-0000-4000-8000-000000000001',
	purpose: 'api_key'
};

const secret = `rk_test_${'a'.repeat(99)}`;

function keyring(
	activeKeyId = 'v1',
	keys: Record<string, string> = { v1: randomBytes(32).toString('base64') }
) {
	return parseStripeCredentialKeyring(JSON.stringify({ activeKeyId, keys }));
}

describe('Stripe credential encryption', () => {
	it('round-trips a secret and never stores it in the clear', () => {
		const ring = keyring();
		const encrypted = encryptStripeSecret(secret, context, ring);

		expect(Buffer.from(encrypted.ciphertext).toString('utf8')).not.toContain('rk_test_');
		expect(encrypted.nonce.byteLength).toBe(12);
		expect(encrypted.authenticationTag.byteLength).toBe(16);
		expect(decryptStripeSecret(encrypted, context, ring)).toBe(secret);
	});

	it('uses a fresh nonce every time', () => {
		const ring = keyring();
		const first = encryptStripeSecret(secret, context, ring);
		const second = encryptStripeSecret(secret, context, ring);
		expect(Buffer.from(first.nonce).equals(Buffer.from(second.nonce))).toBe(false);
	});

	it.each([
		['another organization', { organizationId: 'b2100000-0000-4000-8000-000000000009' }],
		['another connection', { connectionId: 'b2200000-0000-4000-8000-000000000009' }],
		['the other secret column', { purpose: 'webhook_secret' as const }]
	])('refuses a ciphertext moved to %s', (_label, change) => {
		const ring = keyring();
		const encrypted = encryptStripeSecret(secret, context, ring);
		expect(() => decryptStripeSecret(encrypted, { ...context, ...change }, ring)).toThrow(
			StripeCredentialCryptoError
		);
	});

	it('refuses a tampered ciphertext', () => {
		const ring = keyring();
		const encrypted = encryptStripeSecret(secret, context, ring);
		encrypted.ciphertext[0] ^= 1;
		expect(() => decryptStripeSecret(encrypted, context, ring)).toThrow(
			StripeCredentialCryptoError
		);
	});

	it('still decrypts with a retired key after the active key rotates', () => {
		const oldKey = randomBytes(32).toString('base64');
		const encrypted = encryptStripeSecret(secret, context, keyring('v1', { v1: oldKey }));
		const rotated = keyring('v2', { v1: oldKey, v2: randomBytes(32).toString('base64') });
		expect(decryptStripeSecret(encrypted, context, rotated)).toBe(secret);
		expect(encryptStripeSecret(secret, context, rotated).keyId).toBe('v2');
	});

	it.each([
		['missing', undefined],
		['not JSON', 'nope'],
		['a short key', JSON.stringify({ activeKeyId: 'v1', keys: { v1: 'c2hvcnQ=' } })],
		['an active key that is not in the ring', JSON.stringify({ activeKeyId: 'v2', keys: {} })]
	])('rejects a keyring that is %s', (_label, raw) => {
		expect(() => parseStripeCredentialKeyring(raw)).toThrow(StripeCredentialCryptoError);
	});
});
