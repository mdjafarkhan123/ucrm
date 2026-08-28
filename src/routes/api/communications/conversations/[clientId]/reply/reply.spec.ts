import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	OutboundAttachmentError,
	resolveOutboundAttachments
} from '$lib/server/communications/outbound-attachments';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
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
});
