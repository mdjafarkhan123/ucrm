import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
	TwilioCredentialCryptoError,
	decryptTwilioCredential,
	encryptTwilioCredential,
	parseTwilioCredentialKeyring,
	type EncryptedTwilioCredential,
	type TwilioCredentialContext
} from './twilio-credential-crypto';

const organizationId = 'a2100000-0000-4000-8000-000000000001';
const credentialId = 'a2200000-0000-4000-8000-000000000001';
const subaccountSid = `AC${'1'.repeat(32)}`;

const context: TwilioCredentialContext = {
	organizationId,
	credentialId,
	subaccountSid,
	purpose: 'auth_token'
};

function encodedKey(): string {
	return randomBytes(32).toString('base64');
}

function keyring(activeKeyId = 'v1', keys: Record<string, string> = { v1: encodedKey() }) {
	return parseTwilioCredentialKeyring(JSON.stringify({ activeKeyId, keys }));
}

function changed(
	encrypted: EncryptedTwilioCredential,
	field: 'nonce' | 'ciphertext' | 'authenticationTag'
): EncryptedTwilioCredential {
	const bytes = new Uint8Array(encrypted[field]);
	bytes[0] ^= 1;
	return { ...encrypted, [field]: bytes };
}

describe('Twilio credential encryption', () => {
	it('encrypts with the active key and decrypts with authenticated context', () => {
		const keys = keyring();
		const encrypted = encryptTwilioCredential('subaccount-auth-token', context, keys);

		expect(encrypted).toMatchObject({
			algorithm: 'aes-256-gcm',
			formatVersion: 1,
			keyId: 'v1'
		});
		expect(encrypted.nonce).toHaveLength(12);
		expect(encrypted.authenticationTag).toHaveLength(16);
		expect(Buffer.from(encrypted.ciphertext).toString('utf8')).not.toContain(
			'subaccount-auth-token'
		);
		expect(decryptTwilioCredential(encrypted, context, keys)).toBe('subaccount-auth-token');
	});

	it('uses a fresh nonce for each encryption', () => {
		const keys = keyring();
		const first = encryptTwilioCredential('same-secret', context, keys);
		const second = encryptTwilioCredential('same-secret', context, keys);

		expect(Buffer.from(first.nonce).equals(Buffer.from(second.nonce))).toBe(false);
		expect(Buffer.from(first.ciphertext).equals(Buffer.from(second.ciphertext))).toBe(false);
	});

	it('rejects ciphertext moved to another organization, record, subaccount, or purpose', () => {
		const keys = keyring();
		const encrypted = encryptTwilioCredential('bound-secret', context, keys);
		const changedContexts: TwilioCredentialContext[] = [
			{ ...context, organizationId: 'a2100000-0000-4000-8000-000000000002' },
			{ ...context, credentialId: 'a2200000-0000-4000-8000-000000000002' },
			{ ...context, subaccountSid: `AC${'2'.repeat(32)}` },
			{ ...context, purpose: 'restricted_api_key' }
		];

		for (const changedContext of changedContexts) {
			expect(() => decryptTwilioCredential(encrypted, changedContext, keys)).toThrowError(
				TwilioCredentialCryptoError
			);
		}
	});

	it.each(['nonce', 'ciphertext', 'authenticationTag'] as const)(
		'fails closed when %s is changed',
		(field) => {
			const keys = keyring();
			const encrypted = encryptTwilioCredential('tamper-evident-secret', context, keys);

			expect(() => decryptTwilioCredential(changed(encrypted, field), context, keys)).toThrowError(
				'Twilio credential could not be decrypted.'
			);
		}
	);

	it('uses old keys for decryption but only the active key for new encryption', () => {
		const oldKey = encodedKey();
		const newKey = encodedKey();
		const beforeRotation = keyring('v1', { v1: oldKey });
		const encryptedWithOldKey = encryptTwilioCredential('rotating-secret', context, beforeRotation);
		const afterRotation = keyring('v2', { v1: oldKey, v2: newKey });

		expect(decryptTwilioCredential(encryptedWithOldKey, context, afterRotation)).toBe(
			'rotating-secret'
		);
		expect(encryptTwilioCredential('new-secret', context, afterRotation).keyId).toBe('v2');
	});

	it('requires the separately restored keyring when decrypting a serialized database backup', () => {
		const encodedRootKey = encodedKey();
		const originalKeyring = keyring('backup-v1', { 'backup-v1': encodedRootKey });
		const encrypted = encryptTwilioCredential('restore-canary-secret', context, originalKeyring);
		const databaseBackup = JSON.stringify({
			...encrypted,
			nonce: Buffer.from(encrypted.nonce).toString('base64'),
			ciphertext: Buffer.from(encrypted.ciphertext).toString('base64'),
			authenticationTag: Buffer.from(encrypted.authenticationTag).toString('base64')
		});
		const restored = JSON.parse(databaseBackup) as Record<string, unknown>;
		const restoredCredential: EncryptedTwilioCredential = {
			algorithm: 'aes-256-gcm',
			formatVersion: 1,
			keyId: String(restored.keyId),
			nonce: Buffer.from(String(restored.nonce), 'base64'),
			ciphertext: Buffer.from(String(restored.ciphertext), 'base64'),
			authenticationTag: Buffer.from(String(restored.authenticationTag), 'base64')
		};

		expect(databaseBackup).not.toContain('restore-canary-secret');
		expect(() =>
			decryptTwilioCredential(
				restoredCredential,
				context,
				keyring('unrelated', { unrelated: encodedKey() })
			)
		).toThrowError('Twilio credential could not be decrypted.');

		const separatelyRestoredKeyring = parseTwilioCredentialKeyring(
			JSON.stringify({ activeKeyId: 'backup-v1', keys: { 'backup-v1': encodedRootKey } })
		);
		expect(decryptTwilioCredential(restoredCredential, context, separatelyRestoredKeyring)).toBe(
			'restore-canary-secret'
		);
	});

	it('fails safely for a missing decryption key without naming the key or secret', () => {
		const oldKeyring = keyring('retired-key', { 'retired-key': encodedKey() });
		const encrypted = encryptTwilioCredential('never-log-this-secret', context, oldKeyring);
		const replacementKeyring = keyring('current-key', { 'current-key': encodedKey() });

		let failure: unknown;
		try {
			decryptTwilioCredential(encrypted, context, replacementKeyring);
		} catch (error) {
			failure = error;
		}

		expect(failure).toMatchObject({ code: 'decryption_failed' });
		expect(String(failure)).not.toContain('retired-key');
		expect(String(failure)).not.toContain('never-log-this-secret');
	});

	it.each([
		undefined,
		'not-json',
		JSON.stringify({ activeKeyId: 'v1', keys: {} }),
		JSON.stringify({ activeKeyId: 'v1', keys: { v1: 'not-base64' } }),
		JSON.stringify({ activeKeyId: 'bad key id', keys: { 'bad key id': encodedKey() } })
	])('rejects an invalid keyring without echoing its contents', (raw) => {
		expect(() => parseTwilioCredentialKeyring(raw)).toThrowError(
			'Twilio credential encryption is not configured correctly.'
		);
	});

	it('rejects invalid authenticated context before encrypting', () => {
		expect(() =>
			encryptTwilioCredential('secret', { ...context, organizationId: 'not-a-uuid' }, keyring())
		).toThrowError('Twilio credential context is invalid.');
	});
});
