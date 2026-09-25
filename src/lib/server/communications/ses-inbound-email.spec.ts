import { describe, expect, it } from 'vitest';
import {
	parseSesInboundMessage,
	parseSesReceiptNotification,
	sesCandidateRecipients,
	sesInboundEventKey
} from './ses-inbound-email';

function notification(overrides: Partial<Record<string, unknown>> = {}) {
	return {
		notificationType: 'Received',
		mail: { messageId: 'ses-msg-1', timestamp: '2026-09-25T10:00:00.000Z' },
		receipt: {
			recipients: ['r_abc123@reply.upliftcontractor.com'],
			action: { type: 'S3', bucketName: 'ucrm-ses-inbound-mime', objectKey: 'org-1/ses-msg-1' }
		},
		...overrides
	};
}

const plainTextMime = [
	'From: "Jane Doe" <jane@example.com>',
	'To: r_abc123@reply.upliftcontractor.com',
	'Subject: Re: Your quote',
	'Content-Type: text/plain; charset=utf-8',
	'',
	'Thanks, sounds good!'
].join('\r\n');

const autoResponseMime = [
	'From: jane@example.com',
	'To: r_abc123@reply.upliftcontractor.com',
	'Subject: Out of office',
	'Auto-Submitted: auto-replied',
	'Content-Type: text/plain; charset=utf-8',
	'',
	'I am away.'
].join('\r\n');

const withAttachmentMime = [
	'From: jane@example.com',
	'To: r_abc123@reply.upliftcontractor.com',
	'Subject: See attached',
	'Content-Type: multipart/mixed; boundary="BOUNDARY"',
	'',
	'--BOUNDARY',
	'Content-Type: text/plain; charset=utf-8',
	'',
	'Photo attached.',
	'--BOUNDARY',
	'Content-Type: image/jpeg',
	'Content-Disposition: attachment; filename="photo.jpg"',
	'Content-Transfer-Encoding: base64',
	'',
	Buffer.from('fake-image-bytes').toString('base64'),
	'--BOUNDARY--',
	''
].join('\r\n');

describe('parseSesReceiptNotification', () => {
	it('accepts a well-formed S3-action receipt notification', () => {
		expect(parseSesReceiptNotification(notification())).not.toBeNull();
	});

	it('rejects a notification missing the S3 action fields', () => {
		expect(
			parseSesReceiptNotification({
				notificationType: 'Received',
				mail: { messageId: 'x' },
				receipt: { recipients: ['a@b.com'], action: { type: 'S3' } }
			})
		).toBeNull();
	});

	it('rejects a non-Received notification type', () => {
		expect(parseSesReceiptNotification(notification({ notificationType: 'Bounce' }))).toBeNull();
	});
});

describe('sesInboundEventKey', () => {
	it('namespaces the SES message id away from the delivery-events keyspace', () => {
		const parsed = parseSesReceiptNotification(notification())!;
		expect(sesInboundEventKey(parsed)).toBe('ses-inbound:ses-msg-1');
	});
});

describe('sesCandidateRecipients', () => {
	it('builds candidates from the trusted envelope recipients, never MIME headers', () => {
		const parsed = parseSesReceiptNotification(
			notification({
				receipt: { ...notification().receipt, recipients: ['R_ABC@Reply.Example.com'] }
			})
		)!;
		expect(sesCandidateRecipients(parsed)).toEqual([
			{ address: 'r_abc@reply.example.com', local_part: 'r_abc', domain_name: 'reply.example.com' }
		]);
	});
});

describe('parseSesInboundMessage', () => {
	it('parses sender, recipients, subject, and body from a plain-text message', async () => {
		const parsed = parseSesReceiptNotification(notification())!;
		const result = await parseSesInboundMessage(parsed, Buffer.from(plainTextMime));

		expect(result.senderEmail).toBe('jane@example.com');
		expect(result.senderName).toBe('Jane Doe');
		expect(result.subject).toBe('Re: Your quote');
		expect(result.textContent.trim()).toBe('Thanks, sounds good!');
		expect(result.messageKind).toBe('reply');
		expect(result.candidateRecipients).toEqual([
			{
				address: 'r_abc123@reply.upliftcontractor.com',
				local_part: 'r_abc123',
				domain_name: 'reply.upliftcontractor.com'
			}
		]);
		expect(result.attachments).toEqual([]);
	});

	it('classifies an Auto-Submitted header as auto_response, reusing the shared Brevo heuristic', async () => {
		const parsed = parseSesReceiptNotification(notification())!;
		const result = await parseSesInboundMessage(parsed, Buffer.from(autoResponseMime));
		expect(result.messageKind).toBe('auto_response');
	});

	it('classifies a mailer-daemon sender as a delivery notice', async () => {
		const parsed = parseSesReceiptNotification(notification())!;
		const bounceMime = plainTextMime.replace('jane@example.com', 'mailer-daemon@example.com');
		const result = await parseSesInboundMessage(parsed, Buffer.from(bounceMime));
		expect(result.messageKind).toBe('delivery_notice');
	});

	it('extracts an attachment from a multipart message', async () => {
		const parsed = parseSesReceiptNotification(notification())!;
		const result = await parseSesInboundMessage(parsed, Buffer.from(withAttachmentMime));

		expect(result.attachments).toHaveLength(1);
		expect(result.attachments[0].filename).toBe('photo.jpg');
		expect(result.attachments[0].contentType).toBe('image/jpeg');
		expect(result.attachments[0].content.toString()).toBe('fake-image-bytes');
	});
});
