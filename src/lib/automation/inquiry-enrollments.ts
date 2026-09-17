import type {
	EnrollmentCommandResult,
	EnrollmentControl,
	RecordEnrollment
} from '$lib/quotes/automation';

// CRM launch readiness Part 4 Stage 6: the browser client for a website inquiry's follow-up history on its Request
// or chat conversation. Reads `/api/automation/inquiries`; controls go through the shared
// `/api/automation/enrollments/[enrollmentId]` command route.

export type InquiryRecord = { kind: 'request'; id: string } | { kind: 'chat_session'; id: string };

export type InquiryEnrollment = RecordEnrollment & {
	subject_type: 'form_submission' | 'website_chat_session' | string;
	paused_reason: 'staff' | 'customer_reply' | null;
	held_reason: string | null;
};

export type InquiryAutomation = { can_control: boolean; enrollments: InquiryEnrollment[] };

export class InquiryAutomationError extends Error {
	constructor(
		message: string,
		readonly status: number,
		readonly reason?: string
	) {
		super(message);
	}
}

export const inquiryAutomationKey = (record: InquiryRecord) =>
	['automation', 'inquiry', record.kind, record.id] as const;

async function readOrThrow<T>(response: Response, fallback: string): Promise<T> {
	if (!response.ok) {
		const body = (await response.json().catch(() => ({}))) as { error?: string; reason?: string };
		throw new InquiryAutomationError(body.error ?? fallback, response.status, body.reason);
	}
	return response.json();
}

export async function fetchInquiryAutomation(record: InquiryRecord): Promise<InquiryAutomation> {
	const param = record.kind === 'request' ? 'request_id' : 'chat_session_id';
	const response = await fetch(
		`/api/automation/inquiries?${new URLSearchParams({ [param]: record.id }).toString()}`
	);
	return readOrThrow(response, 'Automation history could not be loaded.');
}

export async function controlInquiryEnrollment(
	enrollmentId: string,
	control: EnrollmentControl
): Promise<EnrollmentCommandResult> {
	const response = await fetch(`/api/automation/enrollments/${enrollmentId}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...control, idempotency_key: crypto.randomUUID() })
	});
	return readOrThrow(response, 'That change could not be applied.');
}
