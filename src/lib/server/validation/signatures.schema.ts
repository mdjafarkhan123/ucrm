import { z } from 'zod';
import {
	JOB_SIGNATURE_TYPES,
	SIGNATURE_METHODS,
	SIGNATURE_STATEMENT_MAX,
	SIGNER_NAME_MAX,
	SIGNER_ROLE_MAX
} from '$lib/signatures/types';
import { SIGNATURE_MAX_BYTES } from '$lib/server/storage/signature-image';

// Every limit here has a twin in 20260912100000_job_signatures_foundation.sql. The database is the one
// that decides; this exists so a person gets a sentence about the box they typed in instead of a
// constraint name, and so a body of the wrong shape never starts an upload.

// The base64 ceiling allows for the third that encoding adds to the file.
const SIGNATURE_DATA_URL_MAX = Math.ceil((SIGNATURE_MAX_BYTES * 4) / 3) + 64;

const signatureImageField = z
	.string()
	.max(SIGNATURE_DATA_URL_MAX, 'That signature is too large.')
	.regex(/^data:image\/png;base64,[A-Za-z0-9+/]+={0,2}$/, 'That signature could not be read.');

// Drawn means there is a drawing, typed means there is not. Anything else is a body that half-agrees with
// itself, and the database refuses the same pairing — this just says so in plain words first.
export const collectJobSignatureSchema = z
	.strictObject({
		signature_type: z.enum(JOB_SIGNATURE_TYPES, { message: 'That is not a kind of signature.' }),
		signer_name: z
			.string()
			.trim()
			.min(1, 'Type the name of the person signing.')
			.max(SIGNER_NAME_MAX, 'That name is too long.'),
		signer_role: z
			.string()
			.trim()
			.max(SIGNER_ROLE_MAX, 'That description of the signer is too long.')
			.nullish(),
		statement: z
			.string()
			.trim()
			.min(1, 'Write the sentence the signer is agreeing to.')
			.max(SIGNATURE_STATEMENT_MAX, 'That sentence is too long.'),
		method: z.enum(SIGNATURE_METHODS, { message: 'That is not a way to sign.' }),
		image: signatureImageField.optional(),
		visit_id: z.string().uuid('That visit could not be found.').nullish()
	})
	.refine((value) => (value.method === 'typed') === (value.image === undefined), {
		message: 'That signature is incomplete.',
		path: ['image']
	});

export type CollectJobSignatureInput = z.infer<typeof collectJobSignatureSchema>;
