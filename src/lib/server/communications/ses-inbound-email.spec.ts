import { describe, expect, it } from 'vitest';
import {
	parseSesInboundMessage,
	parseSesReceiptNotification,
	sesCandidateRecipients,
	sesInReplyToProviderMessageId,
	sesInboundEventKey,
	sesSenderAuthenticated
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
		expect(result.inReplyToProviderMessageId).toBeNull();
		expect(result.candidateRecipients).toEqual([
			{
				address: 'r_abc123@reply.upliftcontractor.com',
				local_part: 'r_abc123',
				domain_name: 'reply.upliftcontractor.com'
			}
		]);
		expect(result.attachments).toEqual([]);
	});

	it('links a reply to the SES email it answers through In-Reply-To', async () => {
		const parsed = parseSesReceiptNotification(notification())!;
		const replyMime = plainTextMime.replace(
			'Subject:',
			'In-Reply-To: <0100019a-abc-000000@email.amazonses.com>\r\nSubject:'
		);
		const result = await parseSesInboundMessage(parsed, Buffer.from(replyMime));
		expect(result.inReplyToProviderMessageId).toBe('0100019a-abc-000000');
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

describe('sesInReplyToProviderMessageId', () => {
	it('keeps the bare SES id for regional and us-east-1 Message-IDs', () => {
		expect(sesInReplyToProviderMessageId('<id-1@eu-west-1.amazonses.com>')).toBe('id-1');
		expect(sesInReplyToProviderMessageId('<id-2@email.amazonses.com>')).toBe('id-2');
	});

	it('ignores missing and non-SES Message-IDs', () => {
		expect(sesInReplyToProviderMessageId(undefined)).toBeNull();
		expect(sesInReplyToProviderMessageId('<CAF1x@mail.gmail.com>')).toBeNull();
	});
});

describe('sesSenderAuthenticated', () => {
	function withVerdicts(dkim?: string, dmarc?: string) {
		const base = notification();
		const parsed = parseSesReceiptNotification({
			...base,
			receipt: {
				...base.receipt,
				...(dkim ? { dkimVerdict: { status: dkim } } : {}),
				...(dmarc ? { dmarcVerdict: { status: dmarc } } : {})
			}
		});
		if (!parsed) throw new Error('fixture did not parse');
		return parsed;
	}

	it('trusts a DKIM PASS, which SES reports only when the signing domain matches From', () => {
		expect(sesSenderAuthenticated(withVerdicts('PASS', 'GRAY'), 1)).toBe(true);
	});

	it('trusts a DMARC PASS', () => {
		expect(sesSenderAuthenticated(withVerdicts('GRAY', 'PASS'), 1)).toBe(true);
	});

	it('does not trust GRAY, FAIL, PROCESSING_FAILED, or missing verdicts', () => {
		expect(sesSenderAuthenticated(withVerdicts('GRAY', 'GRAY'), 1)).toBe(false);
		expect(sesSenderAuthenticated(withVerdicts('FAIL', 'FAIL'), 1)).toBe(false);
		expect(sesSenderAuthenticated(withVerdicts('PROCESSING_FAILED', 'PROCESSING_FAILED'), 1)).toBe(
			false
		);
		expect(sesSenderAuthenticated(withVerdicts(), 1)).toBe(false);
	});

	it('never trusts a message with several From addresses, even when SES passed it', () => {
		expect(sesSenderAuthenticated(withVerdicts('PASS', 'PASS'), 2)).toBe(false);
		expect(sesSenderAuthenticated(withVerdicts('PASS', 'PASS'), 0)).toBe(false);
	});

	it('marks a parsed message authenticated from its single From and a passing verdict', async () => {
		const parsed = await parseSesInboundMessage(withVerdicts('PASS'), Buffer.from(plainTextMime));
		expect(parsed.senderAuthenticated).toBe(true);
	});

	it('does not mark a two-From message authenticated', async () => {
		const twoFrom = plainTextMime.replace(
			'From: "Jane Doe" <jane@example.com>',
			'From: attacker@evil.test, jane@example.com'
		);
		const parsed = await parseSesInboundMessage(withVerdicts('PASS'), Buffer.from(twoFrom));
		expect(parsed.senderAuthenticated).toBe(false);
	});
});
