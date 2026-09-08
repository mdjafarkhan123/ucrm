import type { JobSignature, JobSignatureDocument, JobSignatureType } from './types';

export type SignatureApiError = Error & { fieldErrors?: Record<string, string>; reason?: string };

async function throwApiError(response: Response): Promise<never> {
	const result = await response
		.json()
		.catch(
			() => ({}) as { error?: string; field_errors?: Record<string, string>; reason?: string }
		);
	const error = new Error(
		result.error ?? 'That request could not be completed.'
	) as SignatureApiError;
	error.fieldErrors = result.field_errors ?? {};
	error.reason = result.reason;
	throw error;
}

async function requestJson<T>(input: string, init?: RequestInit): Promise<T> {
	const response = await fetch(input, {
		...init,
		headers: init?.body ? { 'content-type': 'application/json', ...init.headers } : init?.headers
	});
	if (!response.ok) return throwApiError(response);
	return response.json();
}

export type JobSignatureRow = JobSignature & { collected_by_name: string | null };

export type JobSignatureList = { signatures: JobSignatureRow[]; can_collect: boolean };

export const jobSignaturesKey = (jobId: string) => ['signatures', 'job', jobId] as const;

export const jobSignatureDocumentKey = (signatureId: string) =>
	['signatures', 'document', signatureId] as const;

export function fetchJobSignatures(jobId: string) {
	return requestJson<JobSignatureList>(`/api/jobs/${jobId}/signatures`);
}

export function fetchJobSignatureDocument(jobId: string, signatureId: string) {
	return requestJson<JobSignatureDocument>(`/api/jobs/${jobId}/signatures/${signatureId}/document`);
}

/** The drawn PNG travels inside this body as a data URL — there is no presigned upload for a signature. */
export function collectJobSignature(
	jobId: string,
	input: {
		signature_type: JobSignatureType;
		signer_name: string;
		signer_role?: string | null;
		statement: string;
		method: 'typed' | 'drawn';
		image?: string;
		visit_id?: string | null;
	}
) {
	return requestJson<{ id: string; collected_at: string; has_image: boolean }>(
		`/api/jobs/${jobId}/signatures`,
		{ method: 'POST', body: JSON.stringify(input) }
	);
}
