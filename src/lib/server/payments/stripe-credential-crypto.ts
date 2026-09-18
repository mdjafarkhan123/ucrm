import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { env } from '$env/dynamic/private';
import { z } from 'zod';

// AES-256-GCM envelopes for a contractor's Stripe restricted key and webhook signing secret. Same keyring
// discipline as twilio-credential-crypto.ts, with its own keyring so a Stripe key can be rotated without
// touching SMS credentials. The authenticated context binds each ciphertext to its organization, connection
// row and purpose, so a ciphertext copied into another row or column cannot be decrypted.

const ALGORITHM = 'aes-256-gcm';
const NONCE_BYTES = 12;
const AUTH_TAG_BYTES = 16;
const KEY_BYTES = 32;
// ASCII unit separator: cannot appear in a UUID or purpose, so no two contexts serialize alike.
const FIELD_SEPARATOR = String.fromCharCode(0x1f);

const keyIdSchema = z.string().regex(/^[A-Za-z0-9._-]{1,64}$/);
const rawKeyringSchema = z
	.object({ activeKeyId: keyIdSchema, keys: z.record(keyIdSchema, z.string().min(1)) })
	.strict();

export type StripeSecretPurpose = 'api_key' | 'webhook_secret';

export type StripeSecretContext = {
	organizationId: string;
	connectionId: string;
	purpose: StripeSecretPurpose;
};

export type StripeCredentialKeyring = {
	activeKeyId: string;
	keys: ReadonlyMap<string, Uint8Array>;
};

export type EncryptedStripeSecret = {
	keyId: string;
	nonce: Uint8Array;
	ciphertext: Uint8Array;
	authenticationTag: Uint8Array;
};

export class StripeCredentialCryptoError extends Error {
	constructor(
		message: string,
		public readonly code: 'invalid_keyring' | 'encryption_failed' | 'decryption_failed'
	) {
		super(message);
		this.name = 'StripeCredentialCryptoError';
	}
}

function decodeEncryptionKey(value: string): Uint8Array | null {
	const decoded = Buffer.from(value, 'base64');
	if (decoded.byteLength !== KEY_BYTES || decoded.toString('base64') !== value) return null;
	return new Uint8Array(decoded);
}

export function parseStripeCredentialKeyring(raw: string | undefined): StripeCredentialKeyring {
	const invalid = () =>
		new StripeCredentialCryptoError(
			'Stripe credential encryption is not configured correctly.',
			'invalid_keyring'
		);

	let parsedJson: unknown;
	try {
		parsedJson = raw ? JSON.parse(raw) : null;
	} catch {
		throw invalid();
	}

	const result = rawKeyringSchema.safeParse(parsedJson);
	if (!result.success || !(result.data.activeKeyId in result.data.keys)) throw invalid();

	const keys = new Map<string, Uint8Array>();
	for (const [keyId, encodedKey] of Object.entries(result.data.keys)) {
		const key = decodeEncryptionKey(encodedKey);
		if (!key) throw invalid();
		keys.set(keyId, key);
	}
	return { activeKeyId: result.data.activeKeyId, keys };
}

/** Lazily required so the application can boot before online payments are configured. */
export function getStripeCredentialKeyring(): StripeCredentialKeyring {
	return parseStripeCredentialKeyring(env.STRIPE_CREDENTIAL_KEYRING);
}

function authenticatedContext(context: StripeSecretContext): Buffer {
	return Buffer.from(
		[
			'ucrm:stripe-credential',
			'1',
			context.organizationId,
			context.connectionId,
			context.purpose
		].join(FIELD_SEPARATOR),
		'utf8'
	);
}

export function encryptStripeSecret(
	plaintext: string,
	context: StripeSecretContext,
	keyring: StripeCredentialKeyring = getStripeCredentialKeyring()
): EncryptedStripeSecret {
	const key = keyring.keys.get(keyring.activeKeyId);
	if (!plaintext || !key) {
		throw new StripeCredentialCryptoError(
			'Stripe credential encryption failed.',
			'encryption_failed'
		);
	}

	const nonce = randomBytes(NONCE_BYTES);
	const cipher = createCipheriv(ALGORITHM, key, nonce, { authTagLength: AUTH_TAG_BYTES });
	cipher.setAAD(authenticatedContext(context));
	const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);

	return {
		keyId: keyring.activeKeyId,
		nonce: new Uint8Array(nonce),
		ciphertext: new Uint8Array(ciphertext),
		authenticationTag: new Uint8Array(cipher.getAuthTag())
	};
}

export function decryptStripeSecret(
	encrypted: EncryptedStripeSecret,
	context: StripeSecretContext,
	keyring: StripeCredentialKeyring = getStripeCredentialKeyring()
): string {
	try {
		const key = keyring.keys.get(encrypted.keyId);
		if (
			!key ||
			encrypted.nonce.byteLength !== NONCE_BYTES ||
			encrypted.authenticationTag.byteLength !== AUTH_TAG_BYTES ||
			encrypted.ciphertext.byteLength === 0
		) {
			throw new Error('invalid envelope');
		}

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
		throw new StripeCredentialCryptoError(
			'Stripe credential could not be decrypted.',
			'decryption_failed'
		);
	}
}
