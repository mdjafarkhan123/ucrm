import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
	ZoomCryptoError,
	decryptZoomTokens,
	encryptZoomTokens,
	parseZoomKeyring
} from './zoom-crypto';

const ring = (
	id = 'v1',
	keys: Record<string, string> = { v1: randomBytes(32).toString('base64') }
) => parseZoomKeyring(JSON.stringify({ activeKeyId: id, keys }));
const tokens = { accessToken: 'access-abc', refreshToken: 'refresh-xyz' };

describe('Zoom credential encryption', () => {
	it('round-trips both tokens and keeps them out of the stored text', () => {
		const keyring = ring();
		const envelope = encryptZoomTokens(tokens, keyring);
		expect(JSON.stringify(envelope)).not.toContain('access-abc');
		expect(decryptZoomTokens(envelope, keyring)).toEqual(tokens);
	});

	it('refuses a tampered envelope or the wrong key', () => {
		const keyring = ring();
		const envelope = encryptZoomTokens(tokens, keyring);
		const flipped = Buffer.from(envelope.ciphertext, 'base64');
		flipped[0] ^= 1;
		expect(() =>
			decryptZoomTokens({ ...envelope, ciphertext: flipped.toString('base64') }, keyring)
		).toThrow(ZoomCryptoError);
		expect(() => decryptZoomTokens(envelope, ring())).toThrow(ZoomCryptoError);
	});

	it('opens an old envelope after the key is rotated', () => {
		const first = randomBytes(32).toString('base64');
		const old = encryptZoomTokens(tokens, ring('v1', { v1: first }));
		const rotated = ring('v2', { v1: first, v2: randomBytes(32).toString('base64') });
		expect(decryptZoomTokens(old, rotated)).toEqual(tokens);
		expect(encryptZoomTokens(tokens, rotated).keyId).toBe('v2');
	});

	it('rejects a missing or malformed keyring', () => {
		expect(() => parseZoomKeyring(undefined)).toThrow(ZoomCryptoError);
		expect(() => parseZoomKeyring('{"activeKeyId":"v1","keys":{"v1":"short"}}')).toThrow(
			ZoomCryptoError
		);
	});
});
