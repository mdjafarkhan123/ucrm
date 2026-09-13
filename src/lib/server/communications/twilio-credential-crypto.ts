import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { env } from '$env/dynamic/private';
import { z } from 'zod';

const ALGORITHM = 'aes-256-gcm' as const;
const FORMAT_VERSION = 1 as const;
const NONCE_BYTES = 12;
const AUTH_TAG_BYTES = 16;
const KEY_BYTES = 32;

const keyIdSchema = z.string().regex(/^[A-Za-z0-9._-]{1,64}$/);
const rawKeyringSchema = z
	.object({
		activeKeyId: keyIdSchema,
		keys: z.record(keyIdSchema, z.string().min(1))
	})
	.strict();

const contextSchema = z
	.object({
		organizationId: z.uuid(),
		credentialId: z.uuid(),
		subaccountSid: z.string().regex(/^AC[0-9A-Fa-f]{32}$/),
		purpose: z.enum(['restricted_api_key', 'auth_token']),
		formatVersion: z.literal(FORMAT_VERSION)
	})
	.strict();

export type TwilioCredentialPurpose = z.infer<typeof contextSchema>['purpose'];

export type TwilioCredentialContext = {
	organizationId: string;
	credentialId: string;
	subaccountSid: string;
	purpose: TwilioCredentialPurpose;
	formatVersion?: typeof FORMAT_VERSION;
};

export type TwilioCredentialKeyring = {
	activeKeyId: string;
	keys: ReadonlyMap<string, Uint8Array>;
};

export type EncryptedTwilioCredential = {
	algorithm: typeof ALGORITHM;
	formatVersion: typeof FORMAT_VERSION;
	keyId: string;
	nonce: Uint8Array;
	ciphertext: Uint8Array;
	authenticationTag: Uint8Array;
};

export class TwilioCredentialCryptoError extends Error {
	constructor(
		message: string,
		public readonly code:
			'invalid_keyring' | 'invalid_context' | 'encryption_failed' | 'decryption_failed'
	) {
		super(message);
		this.name = 'TwilioCredentialCryptoError';
	}
}

function decodeEncryptionKey(value: string): Uint8Array | null {
	try {
		const decoded = Buffer.from(value, 'base64');
		if (decoded.byteLength !== KEY_BYTES || decoded.toString('base64') !== value) return null;
		return new Uint8Array(decoded);
	} catch {
		return null;
	}
}

export function parseTwilioCredentialKeyring(raw: string | undefined): TwilioCredentialKeyring {
	let parsedJson: unknown;
	try {
		parsedJson = raw ? JSON.parse(raw) : null;
	} catch {
		throw new TwilioCredentialCryptoError(
			'Twilio credential encryption is not configured correctly.',
			'invalid_keyring'
		);
	}

	const result = rawKeyringSchema.safeParse(parsedJson);
	if (!result.success || !(result.data.activeKeyId in result.data.keys)) {
		throw new TwilioCredentialCryptoError(
			'Twilio credential encryption is not configured correctly.',
			'invalid_keyring'
		);
	}

	const keys = new Map<string, Uint8Array>();
	for (const [keyId, encodedKey] of Object.entries(result.data.keys)) {
		const key = decodeEncryptionKey(encodedKey);
		if (!key) {
			throw new TwilioCredentialCryptoError(
				'Twilio credential encryption is not configured correctly.',
				'invalid_keyring'
			);
		}
		keys.set(keyId, key);
	}

	return { activeKeyId: result.data.activeKeyId, keys };
}

/** Lazily required so the application can boot before SMS provisioning is enabled. */
export function getTwilioCredentialKeyring(): TwilioCredentialKeyring {
	return parseTwilioCredentialKeyring(env.TWILIO_CREDENTIAL_KEYRING);
}

function authenticatedContext(context: TwilioCredentialContext): Uint8Array {
	const result = contextSchema.safeParse({
		...context,
		formatVersion: context.formatVersion ?? FORMAT_VERSION
	});
	if (!result.success) {
		throw new TwilioCredentialCryptoError(
			'Twilio credential context is invalid.',
			'invalid_context'
		);
	}

	const value = result.data;
	return Buffer.from(
		[
			'ucrm:twilio-credential',
			String(value.formatVersion),
			value.organizationId,
			value.credentialId,
			value.subaccountSid,
			value.purpose
		].join('\u001f'),
		'utf8'
	);
}

export function encryptTwilioCredential(
	plaintext: string,
	context: TwilioCredentialContext,
	keyring: TwilioCredentialKeyring = getTwilioCredentialKeyring()
): EncryptedTwilioCredential {
	if (!plaintext) {
		throw new TwilioCredentialCryptoError(
			'Twilio credential encryption failed.',
			'encryption_failed'
		);
	}

	const key = keyring.keys.get(keyring.activeKeyId);
	if (!key || key.byteLength !== KEY_BYTES) {
		throw new TwilioCredentialCryptoError(
			'Twilio credential encryption is not available.',
			'encryption_failed'
		);
	}

	try {
		const nonce = randomBytes(NONCE_BYTES);
		const cipher = createCipheriv(ALGORITHM, key, nonce, { authTagLength: AUTH_TAG_BYTES });
		cipher.setAAD(authenticatedContext(context));
		const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);

		return {
			algorithm: ALGORITHM,
			formatVersion: FORMAT_VERSION,
			keyId: keyring.activeKeyId,
			nonce: new Uint8Array(nonce),
			ciphertext: new Uint8Array(ciphertext),
			authenticationTag: new Uint8Array(cipher.getAuthTag())
		};
	} catch (error) {
		if (error instanceof TwilioCredentialCryptoError) throw error;
		throw new TwilioCredentialCryptoError(
			'Twilio credential encryption failed.',
			'encryption_failed'
		);
	}
}

export function decryptTwilioCredential(
	encrypted: EncryptedTwilioCredential,
	context: TwilioCredentialContext,
	keyring: TwilioCredentialKeyring = getTwilioCredentialKeyring()
): string {
	try {
		if (
			encrypted.algorithm !== ALGORITHM ||
			encrypted.formatVersion !== FORMAT_VERSION ||
			!keyIdSchema.safeParse(encrypted.keyId).success ||
			encrypted.nonce.byteLength !== NONCE_BYTES ||
			encrypted.authenticationTag.byteLength !== AUTH_TAG_BYTES ||
			encrypted.ciphertext.byteLength === 0
		) {
			throw new Error('invalid envelope');
		}

		const key = keyring.keys.get(encrypted.keyId);
		if (!key || key.byteLength !== KEY_BYTES) throw new Error('key unavailable');

		const decipher = createDecipheriv(ALGORITHM, key, encrypted.nonce, {
			authTagLength: AUTH_TAG_BYTES
		});
		decipher.setAAD(authenticatedContext(context));
		decipher.setAuthTag(encrypted.authenticationTag);
		const plaintext = Buffer.concat([decipher.update(encrypted.ciphertext), decipher.final()]);
		try {
			return plaintext.toString('utf8');
		} finally {
			plaintext.fill(0);
		}
	} catch {
		throw new TwilioCredentialCryptoError(
			'Twilio credential could not be decrypted.',
			'decryption_failed'
		);
	}
}
