import { beforeEach, describe, expect, it, vi } from 'vitest';
import { headObject } from '$lib/server/storage/r2';
import { OutboundAttachmentError, resolveOutboundAttachments } from './outbound-attachments';

vi.mock('$lib/server/storage/r2', () => ({ headObject: vi.fn() }));

const organizationId = 'org-1';
const objectKey = `${organizationId}/outbound-email-attachments/i/quote.pdf`;

describe('resolveOutboundAttachments', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('returns an empty list without touching storage when there are no attachments', async () => {
		const result = await resolveOutboundAttachments(organizationId, []);
		expect(result).toEqual([]);
		expect(headObject).not.toHaveBeenCalled();
	});

	it('measures each file from storage rather than trusting the browser-declared size', async () => {
		vi.mocked(headObject).mockResolvedValue({
			contentType: 'application/pdf',
			contentLength: 2048
		});

		const result = await resolveOutboundAttachments(organizationId, [
			{ object_key: objectKey, file_name: 'quote.pdf', mime_type: 'application/octet-stream' }
		]);

		expect(result).toEqual([
			{
				file_name: 'quote.pdf',
				mime_type: 'application/pdf',
				byte_size: 2048,
				object_key: objectKey
			}
		]);
	});

	it('rejects an object key stored under another organization', async () => {
		await expect(
			resolveOutboundAttachments(organizationId, [
				{
					object_key: 'other-org/outbound-email-attachments/i/quote.pdf',
					file_name: 'quote.pdf',
					mime_type: 'application/pdf'
				}
			])
		).rejects.toThrow(OutboundAttachmentError);
		expect(headObject).not.toHaveBeenCalled();
	});

	it('rejects a file whose upload never landed in storage', async () => {
		vi.mocked(headObject).mockRejectedValue(new Error('NotFound'));

		await expect(
			resolveOutboundAttachments(organizationId, [
				{ object_key: objectKey, file_name: 'quote.pdf', mime_type: 'application/pdf' }
			])
		).rejects.toThrow(OutboundAttachmentError);
	});

	it('rejects when the combined measured size exceeds the 20 MB total', async () => {
		vi.mocked(headObject).mockResolvedValue({
			contentType: 'application/pdf',
			contentLength: 15 * 1024 * 1024
		});

		await expect(
			resolveOutboundAttachments(organizationId, [
				{ object_key: `${objectKey}-1`, file_name: 'a.pdf', mime_type: 'application/pdf' },
				{ object_key: `${objectKey}-2`, file_name: 'b.pdf', mime_type: 'application/pdf' }
			])
		).rejects.toThrow('Attachments must total 20 MB or less.');
	});
});
