import type { SmsTollfreeBusiness } from '$lib/server/validation/communications-sms-tollfree.schema';

// The toll-free check's form (Stage 10 Part 4c, `concept.pen` board `SCpaW`): one check per toll-free number,
// saved as a draft while it is filled in, then sent to Twilio for the carriers' review.

export type TollfreeBusiness = SmsTollfreeBusiness;
export type TollfreeAddress = TollfreeBusiness['business_address'];
export type TollfreeStatus = 'draft' | 'sending' | 'under_review' | 'approved' | 'needs_fix';

export type TollfreePicture = {
	id: string;
	public_token: string;
	file_name: string;
	size_bytes: number;
	created_at: string;
};

export type TollfreeDetail = {
	phone_number: string;
	registration_address: Partial<TollfreeAddress> | null;
	check: {
		id: string;
		status: TollfreeStatus;
		answers: { business?: Partial<TollfreeBusiness> };
		revision: number;
		failure_reason: string | null;
		edit_expires_at: string | null;
		submitted_at: string | null;
	} | null;
	pictures: TollfreePicture[];
};

/** A refused request: the server's words, its status, and each answer it found wrong. */
export type TollfreeRequestError = Error & {
	status: number;
	/** `stale`: another tab changed the check first. */
	code?: 'stale';
	fieldErrors?: { field: string; message: string }[];
};

export const tollfreeKey = (senderId: string) =>
	['settings', 'communications', 'sms', 'toll-free', senderId] as const;

/** The address Twilio's carriers can read a proof picture at; same-origin, so it also draws the preview. */
export const tollfreePictureUrl = (token: string) => `/api/public/sms/toll-free-proof/${token}`;

export const TOLLFREE_PICTURE_LIMIT = 5;
export const TOLLFREE_PICTURE_MAX_BYTES = 5 * 1024 * 1024;

function refused(status: number, result: Record<string, unknown>, fallback: string) {
	const error = new Error(
		typeof result.error === 'string' ? result.error : fallback
	) as TollfreeRequestError;
	error.status = status;
	if (status === 409) error.code = 'stale';
	if (Array.isArray(result.field_errors))
		error.fieldErrors = result.field_errors as TollfreeRequestError['fieldErrors'];
	return error;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
	const response = await fetch(path, init);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw refused(response.status, result, 'The toll-free check could not be saved.');
	return result as T;
}

const path = (senderId: string) => `/api/settings/communications/sms/toll-free/${senderId}`;
const jsonInit = (method: string, body: unknown): RequestInit => ({
	method,
	headers: { 'content-type': 'application/json' },
	body: JSON.stringify(body)
});

type Saved = { revision: number; pictures: TollfreePicture[] };

export const fetchTollfreeCheck = (senderId: string) => request<TollfreeDetail>(path(senderId));
export const startTollfreeCheck = (senderId: string) =>
	request<TollfreeDetail>(path(senderId), { method: 'POST' });
export const saveTollfreeCheck = (
	senderId: string,
	revision: number,
	business: Partial<TollfreeBusiness>
) =>
	request<TollfreeDetail>(
		path(senderId),
		jsonInit('PATCH', { expected_revision: revision, business })
	);
export const sendTollfreeCheck = (senderId: string, revision: number) =>
	request<{ status: string }>(
		`${path(senderId)}/send`,
		jsonInit('POST', { expected_revision: revision })
	);
export const removeTollfreePicture = (senderId: string, id: string, revision: number) =>
	request<Saved>(
		`${path(senderId)}/pictures`,
		jsonInit('DELETE', { id, expected_revision: revision })
	);

/** Send one picture with its progress (0 to 1); fetch can't report upload progress, so this uses XHR. */
export function uploadTollfreePicture(
	senderId: string,
	revision: number,
	file: File,
	onProgress: (fraction: number) => void
): Promise<Saved & { id: string }> {
	return new Promise((done, fail) => {
		const form = new FormData();
		form.set('picture', file);
		form.set('expected_revision', String(revision));
		const xhr = new XMLHttpRequest();
		xhr.open('POST', `${path(senderId)}/pictures`);
		xhr.upload.onprogress = (event) => {
			if (event.lengthComputable) onProgress(event.loaded / event.total);
		};
		xhr.onload = () => {
			let result: Record<string, unknown> = {};
			try {
				result = JSON.parse(xhr.responseText || '{}');
			} catch {
				// A proxy's error page: fall back to the plain message below.
			}
			if (xhr.status >= 200 && xhr.status < 300) done(result as Saved & { id: string });
			else fail(refused(xhr.status, result, 'The picture did not upload.'));
		};
		xhr.onerror = () => fail(refused(0, {}, 'The picture did not upload. Check your connection.'));
		xhr.send(form);
	});
}
