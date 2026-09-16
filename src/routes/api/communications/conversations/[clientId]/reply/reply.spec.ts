import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	OutboundAttachmentError,
	resolveOutboundAttachments
} from '$lib/server/communications/outbound-attachments';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { headObject } from '$lib/server/storage/r2';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', () => ({
	hasPermission: vi.fn(),
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/communications/outbound-attachments', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/communications/outbound-attachments')>()),
	resolveOutboundAttachments: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/storage/r2', () => ({ headObject: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';
const clientId = '123e4567-e89b-12d3-a456-426614174002';

function event(body: unknown) {
	return {
		params: { clientId },
		request: new Request(`http://localhost/api/communications/conversations/${clientId}/reply`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof POST>[0];
}

const validBody = {
	subject: 'Re: A quick update',
	body: 'Hello <script>alert(1)</script>',
	idempotency_key: '123e4567-e89b-12d3-a456-426614174004'
};

describe('conversation reply API', () => {
	const rpc = vi.fn();

	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { user: { id: userId }, organization: { id: organizationId } },
			access: { features: {}, limits: {}, permissions: {} }
		} as never);
		vi.mocked(hasPermission).mockReturnValue(true);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		vi.mocked(resolveOutboundAttachments).mockResolvedValue([]);
		vi.mocked(headObject).mockResolvedValue({ contentType: 'image/jpeg', contentLength: 2048 });
		rpc.mockResolvedValue({
			data: { id: 'intent-1', status: 'queued', created_at: '2026-08-25T00:00:00.000Z' },
			error: null
		});
	});

	it('stops before validation or service access when sending is not permitted', async () => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await POST(event(validBody));
		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('does not let sending permission bypass customer visibility', async () => {
		vi.mocked(hasPermission).mockReturnValue(false);

		const response = await POST(event(validBody));
		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('never accepts a browser-supplied recipient -- only ids and plain text reach the command', async () => {
		const response = await POST(event(validBody));
		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('enqueue_conversation_reply_email', {
			target_organization_id: organizationId,
			target_actor_user_id: userId,
			target_client_id: clientId,
			target_logical_send_key: validBody.idempotency_key,
			target_subject: validBody.subject,
			target_html_content: '<p>Hello &lt;script&gt;alert(1)&lt;/script&gt;</p>',
			target_text_content: validBody.body,
			target_attachments: []
		});
	});

	it('rejects an invalid body before accessing the service role', async () => {
		const response = await POST(event({ ...validBody, body: '' }));
		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('surfaces a database rejection as a validation error', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '23503', message: 'This customer has no active email address to reply to.' }
		});
		const response = await POST(event(validBody));
		expect(response.status).toBe(422);
	});

	it('resolves attachments before enqueuing and forwards the resolved list to the command', async () => {
		const resolved = [
			{
				file_name: 'quote.pdf',
				mime_type: 'application/pdf',
				byte_size: 1024,
				object_key: `${organizationId}/outbound-email-attachments/i/quote.pdf`
			}
		];
		vi.mocked(resolveOutboundAttachments).mockResolvedValue(resolved);

		const response = await POST(
			event({
				...validBody,
				attachments: [
					{
						object_key: resolved[0].object_key,
						file_name: resolved[0].file_name,
						mime_type: resolved[0].mime_type
					}
				]
			})
		);

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith(
			'enqueue_conversation_reply_email',
			expect.objectContaining({ target_attachments: resolved })
		);
	});

	it('rejects the reply, without calling the send command, when an attachment cannot be resolved', async () => {
		vi.mocked(resolveOutboundAttachments).mockRejectedValue(
			new OutboundAttachmentError('That file does not belong to this business.')
		);

		const response = await POST(
			event({
				...validBody,
				attachments: [
					{
						object_key: 'other-org/outbound-email-attachments/i/x.pdf',
						file_name: 'x.pdf',
						mime_type: 'application/pdf'
					}
				]
			})
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	describe('sms channel', () => {
		const validSmsBody = {
			channel: 'sms',
			body: 'On our way over.',
			idempotency_key: '123e4567-e89b-12d3-a456-426614174005'
		};

		it('calls the SMS reply command with only ids and plain text, never a browser-chosen recipient', async () => {
			const response = await POST(event(validSmsBody));
			expect(response.status).toBe(201);
			expect(rpc).toHaveBeenCalledWith('enqueue_conversation_reply_sms', {
				target_organization_id: organizationId,
				target_actor_user_id: userId,
				target_client_id: clientId,
				target_logical_send_key: validSmsBody.idempotency_key,
				target_body: validSmsBody.body,
				target_attachments: []
			});
			expect(resolveOutboundAttachments).not.toHaveBeenCalled();
		});

		it('resolves and forwards a single attached photo through resolveOutboundSmsAttachment', async () => {
			const photo = {
				object_key: `${organizationId}/outbound-sms-attachments/photo.jpg`,
				file_name: 'photo.jpg',
				mime_type: 'image/jpeg'
			};
			const response = await POST(event({ ...validSmsBody, attachments: [photo] }));
			expect(response.status).toBe(201);
			expect(rpc).toHaveBeenCalledWith(
				'enqueue_conversation_reply_sms',
				expect.objectContaining({
					target_attachments: [expect.objectContaining({ object_key: photo.object_key })]
				})
			);
		});

		it('rejects an attached photo stored under another organization before calling the database', async () => {
			const response = await POST(
				event({
					...validSmsBody,
					attachments: [
						{
							object_key: 'other-org/outbound-sms-attachments/photo.jpg',
							file_name: 'photo.jpg',
							mime_type: 'image/jpeg'
						}
					]
				})
			);
			expect(response.status).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		});

		it('rejects an empty SMS body before accessing the service role', async () => {
			const response = await POST(event({ ...validSmsBody, body: '' }));
			expect(response.status).toBe(422);
			expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
		});

		it('surfaces a P0001 safety refusal (consent/balance/quiet hours) as a validation error', async () => {
			rpc.mockResolvedValue({
				data: null,
				error: {
					code: 'P0001',
					message: 'There is no SMS consent on file for this customer and message type.'
				}
			});
			const response = await POST(event(validSmsBody));
			expect(response.status).toBe(422);
			const result = await response.json();
			expect(result.error).toBe(
				'There is no SMS consent on file for this customer and message type.'
			);
		});

		it('surfaces a same-key payload conflict as a validation error', async () => {
			rpc.mockResolvedValue({
				data: null,
				error: { code: '23505', message: 'This message was already queued with different details.' }
			});
			const response = await POST(event(validSmsBody));
			expect(response.status).toBe(422);
		});
	});
});
