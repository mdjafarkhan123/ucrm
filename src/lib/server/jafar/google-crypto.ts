import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { env } from '$env/dynamic/private';
import { z } from 'zod';

// Jafar business management E5: AES-256-GCM envelope for Jafar's Google tokens, with the same keyring discipline as
// the Stripe keys (payments/stripe-credential-crypto.ts) and its own keyring so each can rotate alone. Both tokens
// travel in one envelope. The authenticated context binds it to Google and its purpose, so a ciphertext copied
// into another column cannot be opened.

const ALGORITHM = 'aes-256-gcm';
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const KEY_BYTES = 32;
const CONTEXT = 'ucrm:google-credential\u001f1\u001ftokens';

const keyIdSchema = z.string().regex(/^[A-Za-z0-9._-]{1,64}$/);
const keyringSchema = z
	.object({ activeKeyId: keyIdSchema, keys: z.record(keyIdSchema, z.string().min(1)) })
	.strict();

export type GoogleTokens = { accessToken: string; refreshToken: string };

/** The envelope as the database keeps it: each part in base64. */
export type GoogleEnvelope = { keyId: string; nonce: string; ciphertext: string; tag: string };

export type GoogleKeyring = { activeKeyId: string; keys: ReadonlyMap<string, Uint8Array> };

export class GoogleCryptoError extends Error {
	constructor(
		message: string,
		public readonly code: 'invalid_keyring' | 'encryption_failed' | 'decryption_failed'
	) {
		super(message);
		this.name = 'GoogleCryptoError';
	}
}

export function parseGoogleKeyring(raw: string | undefined): GoogleKeyring {
	const invalid = () =>
		new GoogleCryptoError(
			'Google credential encryption is not configured correctly.',
			'invalid_keyring'
		);
	let json: unknown;
	try {
		json = raw ? JSON.parse(raw) : null;
	} catch {
		throw invalid();
	}
	const parsed = keyringSchema.safeParse(json);
	if (!parsed.success || !(parsed.data.activeKeyId in parsed.data.keys)) throw invalid();
	const keys = new Map<string, Uint8Array>();
	for (const [id, encoded] of Object.entries(parsed.data.keys)) {
		const decoded = Buffer.from(encoded, 'base64');
		if (decoded.byteLength !== KEY_BYTES || decoded.toString('base64') !== encoded) throw invalid();
		keys.set(id, new Uint8Array(decoded));
	}
	return { activeKeyId: parsed.data.activeKeyId, keys };
}

export const getGoogleKeyring = () => parseGoogleKeyring(env.GOOGLE_CREDENTIAL_KEYRING);

export function encryptGoogleTokens(
	tokens: GoogleTokens,
	keyring: GoogleKeyring = getGoogleKeyring()
): GoogleEnvelope {
	const key = keyring.keys.get(keyring.activeKeyId);
	if (!tokens.accessToken || !tokens.refreshToken || !key)
		throw new GoogleCryptoError('Google credential encryption failed.', 'encryption_failed');
	const nonce = randomBytes(NONCE_BYTES);
	const cipher = createCipheriv(ALGORITHM, key, nonce, { authTagLength: TAG_BYTES });
	cipher.setAAD(Buffer.from(CONTEXT, 'utf8'));
	const ciphertext = Buffer.concat([cipher.update(JSON.stringify(tokens), 'utf8'), cipher.final()]);
	return {
		keyId: keyring.activeKeyId,
		nonce: nonce.toString('base64'),
		ciphertext: ciphertext.toString('base64'),
		tag: cipher.getAuthTag().toString('base64')
	};
}

export function decryptGoogleTokens(
	envelope: GoogleEnvelope,
	keyring: GoogleKeyring = getGoogleKeyring()
): GoogleTokens {
	try {
		const key = keyring.keys.get(envelope.keyId);
		const nonce = Buffer.from(envelope.nonce, 'base64');
		const tag = Buffer.from(envelope.tag, 'base64');
		const ciphertext = Buffer.from(envelope.ciphertext, 'base64');
		if (
			!key ||
			nonce.byteLength !== NONCE_BYTES ||
			tag.byteLength !== TAG_BYTES ||
			!ciphertext.length
		)
			throw new Error('invalid envelope');
		const decipher = createDecipheriv(ALGORITHM, key, nonce, { authTagLength: TAG_BYTES });
		decipher.setAAD(Buffer.from(CONTEXT, 'utf8'));
		decipher.setAuthTag(tag);
		const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
		const parsed = z
			.object({ accessToken: z.string().min(1), refreshToken: z.string().min(1) })
			.parse(JSON.parse(plain.toString('utf8')));
		plain.fill(0);
		return parsed;
	} catch {
		throw new GoogleCryptoError('Google credential could not be decrypted.', 'decryption_failed');
	}
}
