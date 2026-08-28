import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { createPresignedUploadUrl } from '$lib/server/storage/r2';

vi.mock('$lib/server/access/permission', () => ({
	hasPermission: vi.fn(),
	requireOrganizationPermission: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/storage/r2', () => ({
	buildOutboundEmailAttachmentObjectKey: (organizationId: string, fileName: string) =>
		`${organizationId}/outbound-email-attachments/fixed-uuid-${fileName}`,
	createPresignedUploadUrl: vi.fn()
}));

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const userId = '123e4567-e89b-12d3-a456-426614174001';

function event(body: unknown) {
	return {
		params: {},
		request: new Request('http://localhost/api/communications/attachments/presign-upload', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof POST>[0];
}

const validBody = { file_name: 'quote.pdf', mime_type: 'application/pdf', size_bytes: 1024 };

describe('outbound attachment presign API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { user: { id: userId }, organization: { id: organizationId } },
			access: { features: {}, limits: {}, permissions: {} }
		} as never);
		vi.mocked(hasPermission).mockReturnValue(true);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({} as never);
		vi.mocked(createPresignedUploadUrl).mockResolvedValue('https://r2.example.test/upload');
	});

	it('stops before validation when sending is not permitted', async () => {
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await POST(event(validBody));
		expect(response.status).toBe(403);
		expect(createPresignedUploadUrl).not.toHaveBeenCalled();
	});

	it('does not let sending permission bypass customer visibility', async () => {
		vi.mocked(hasPermission).mockReturnValue(false);

		const response = await POST(event(validBody));
		expect(response.status).toBe(403);
		expect(createPresignedUploadUrl).not.toHaveBeenCalled();
	});

	it('issues an org-scoped key under the outbound-email-attachments prefix', async () => {
		const response = await POST(event(validBody));
		expect(response.status).toBe(200);
		const payload = await response.json();
		expect(payload.object_key).toBe(
			`${organizationId}/outbound-email-attachments/fixed-uuid-quote.pdf`
		);
		expect(payload.upload_url).toBe('https://r2.example.test/upload');
	});

	it('rejects a dangerous file extension before ever presigning', async () => {
		const response = await POST(event({ ...validBody, file_name: 'invoice.exe' }));
		expect(response.status).toBe(422);
		expect(createPresignedUploadUrl).not.toHaveBeenCalled();
	});

	it('rejects a file over the 20 MB cap', async () => {
		const response = await POST(event({ ...validBody, size_bytes: 21 * 1024 * 1024 }));
		expect(response.status).toBe(422);
		expect(createPresignedUploadUrl).not.toHaveBeenCalled();
	});
});
