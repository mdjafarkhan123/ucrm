import { httpError } from '$lib/http-error';
import type { SmsRegistrationAnswers } from '$lib/server/validation/communications-sms-registration.schema';

export type TollfreePicture = {
	id: string;
	public_token: string;
	file_name: string;
	size_bytes: number;
	created_at: string;
};

export type TollfreeDetail = {
	phone_number: string;
	check: {
		id: string;
		status: 'draft' | 'sending' | 'under_review' | 'approved' | 'needs_fix';
		answers: { business?: Partial<SmsRegistrationAnswers> };
		revision: number;
		failure_reason: string | null;
		edit_expires_at: string | null;
		submitted_at: string | null;
	} | null;
	pictures: TollfreePicture[];
};

export const tollfreeKey = (senderId: string) =>
	['settings', 'communications', 'sms', 'toll-free', senderId] as const;

async function request<T>(path: string, init?: RequestInit): Promise<T> {
	const response = await fetch(path, init);
	const result = await response.json().catch(() => ({}));
	if (!response.ok)
		throw httpError(response, result.error ?? 'The toll-free check could not be saved.');
	return result as T;
}

const path = (senderId: string) => `/api/settings/communications/sms/toll-free/${senderId}`;
const jsonInit = (method: string, body: unknown): RequestInit => ({
	method,
	headers: { 'content-type': 'application/json' },
	body: JSON.stringify(body)
});

export const fetchTollfreeCheck = (senderId: string) => request<TollfreeDetail>(path(senderId));
export const startTollfreeCheck = (senderId: string) =>
	request<TollfreeDetail>(path(senderId), { method: 'POST' });
export const saveTollfreeCheck = (
	senderId: string,
	revision: number,
	business: Partial<SmsRegistrationAnswers>
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
	request<{ revision: number; pictures: TollfreePicture[] }>(
		`${path(senderId)}/pictures`,
		jsonInit('DELETE', { id, expected_revision: revision })
	);
