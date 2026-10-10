import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
	GoogleCryptoError,
	decryptGoogleTokens,
	encryptGoogleTokens,
	parseGoogleKeyring
} from './google-crypto';

const ring = (
	id = 'v1',
	keys: Record<string, string> = { v1: randomBytes(32).toString('base64') }
) => parseGoogleKeyring(JSON.stringify({ activeKeyId: id, keys }));
const tokens = { accessToken: 'access-abc', refreshToken: 'refresh-xyz' };

describe('Google credential encryption', () => {
	it('round-trips both tokens and keeps them out of the stored text', () => {
		const keyring = ring();
		const envelope = encryptGoogleTokens(tokens, keyring);
		expect(JSON.stringify(envelope)).not.toContain('access-abc');
		expect(decryptGoogleTokens(envelope, keyring)).toEqual(tokens);
	});

	it('refuses a tampered envelope or the wrong key', () => {
		const keyring = ring();
		const envelope = encryptGoogleTokens(tokens, keyring);
		const flipped = Buffer.from(envelope.ciphertext, 'base64');
		flipped[0] ^= 1;
		expect(() =>
			decryptGoogleTokens({ ...envelope, ciphertext: flipped.toString('base64') }, keyring)
		).toThrow(GoogleCryptoError);
		expect(() => decryptGoogleTokens(envelope, ring())).toThrow(GoogleCryptoError);
	});

	it('opens an old envelope after the key is rotated', () => {
		const first = randomBytes(32).toString('base64');
		const old = encryptGoogleTokens(tokens, ring('v1', { v1: first }));
		const rotated = ring('v2', { v1: first, v2: randomBytes(32).toString('base64') });
		expect(decryptGoogleTokens(old, rotated)).toEqual(tokens);
		expect(encryptGoogleTokens(tokens, rotated).keyId).toBe('v2');
	});

	it('rejects a missing or malformed keyring', () => {
		expect(() => parseGoogleKeyring(undefined)).toThrow(GoogleCryptoError);
		expect(() => parseGoogleKeyring('{"activeKeyId":"v1","keys":{"v1":"short"}}')).toThrow(
			GoogleCryptoError
		);
	});
});
