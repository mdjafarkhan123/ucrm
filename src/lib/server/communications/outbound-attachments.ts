import { headObject } from '$lib/server/storage/r2';
import { INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES } from '$lib/server/communications/inbound-email';

export type OutboundAttachmentInput = { object_key: string; file_name: string; mime_type: string };

export type ResolvedOutboundAttachment = {
	file_name: string;
	mime_type: string;
	byte_size: number;
	object_key: string;
};

export class OutboundAttachmentError extends Error {}

// Shared by every send route (reply, manual/New conversation). Re-measures each file from storage rather
// than trusting the browser's claim -- the same reason logo and quote-representative uploads call
// headObject before their commit -- and checks the org prefix and 20 MB total up front so a bad upload
// fails with a readable message instead of the database's generic errcode. The private
// attach_communication_outbound_files command re-enforces both, since this check is advisory only.
export async function resolveOutboundAttachments(
	organizationId: string,
	attachments: OutboundAttachmentInput[]
): Promise<ResolvedOutboundAttachment[]> {
	if (attachments.length === 0) return [];

	// Checked up front, before any network round trip: an invalid prefix on one file means none of
	// them need to be measured.
	const prefix = `${organizationId}/outbound-email-attachments/`;
	for (const attachment of attachments) {
		if (!attachment.object_key.startsWith(prefix)) {
			throw new OutboundAttachmentError('That file does not belong to this business.');
		}
	}

	// At most 10 files (the Zod cap), so this is a bounded fan-out, not unbounded -- and each HeadObject
	// is independent, so awaiting them one at a time would only add up their latencies for no reason.
	const heads = await Promise.all(
		attachments.map(async (attachment) => {
			try {
				return await headObject(attachment.object_key);
			} catch {
				throw new OutboundAttachmentError('That upload did not finish. Try again.');
			}
		})
	);

	let totalBytes = 0;
	const resolved = attachments.map((attachment, index) => {
		const byteSize = heads[index].contentLength ?? 0;
		if (byteSize <= 0) {
			throw new OutboundAttachmentError('That upload did not finish. Try again.');
		}
		totalBytes += byteSize;
		return {
			file_name: attachment.file_name,
			mime_type: heads[index].contentType ?? attachment.mime_type,
			byte_size: byteSize,
			object_key: attachment.object_key
		};
	});

	if (totalBytes > INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES) {
		throw new OutboundAttachmentError('Attachments must total 20 MB or less.');
	}

	return resolved;
}
