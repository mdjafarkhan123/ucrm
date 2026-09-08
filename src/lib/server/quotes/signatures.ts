import { buildSignatureObjectKey } from '$lib/server/storage/r2';
import { storeSignatureImageAt, type SignatureImage } from '$lib/server/storage/signature-image';

// The quote side of signature storage. Everything about reading and validating the drawn PNG lives in
// `$lib/server/storage/signature-image` and is shared with job signatures (15d-1); the only thing left
// here is which prefix a quote's signature lands under.

export {
	SIGNATURE_MIME_TYPE,
	SIGNATURE_MAX_BYTES,
	decodeSignatureImage,
	discardSignatureImage,
	type SignatureImage
} from '$lib/server/storage/signature-image';

export async function storeSignatureImage(
	organizationId: string,
	quoteId: string,
	image: SignatureImage
): Promise<string> {
	return storeSignatureImageAt(buildSignatureObjectKey(organizationId, quoteId), image);
}
