import { describe, expect, it, vi } from 'vitest';
import { awsSnsSignatureCheck, trustedSubscribeUrl, verifySnsMessage } from './sns-webhook';

const TOPIC = 'arn:aws:sns:us-east-1:123456789012:ucrm-ses-inbound';

function message(overrides: Record<string, unknown> = {}) {
	return {
		Type: 'Notification',
		MessageId: 'b3f1c1a2-0000-4000-8000-000000000001',
		TopicArn: TOPIC,
		Message: '{}',
		Timestamp: '2026-09-25T12:00:00.000Z',
		SignatureVersion: '2',
		Signature: 'c2ln',
		SigningCertURL: 'https://sns.us-east-1.amazonaws.com/SimpleNotificationService-abc.pem',
		...overrides
	};
}

describe('verifySnsMessage', () => {
	it('accepts a correctly signed message from our topic', async () => {
		const check = vi.fn().mockResolvedValue(undefined);
		const envelope = await verifySnsMessage(JSON.stringify(message()), TOPIC, check);
		expect(envelope?.Type).toBe('Notification');
		expect(check).toHaveBeenCalledOnce();
	});

	it('refuses a bad signature', async () => {
		const check = vi.fn().mockRejectedValue(new Error('The message signature is invalid.'));
		expect(await verifySnsMessage(JSON.stringify(message()), TOPIC, check)).toBeNull();
	});

	it('refuses a genuine message from another topic without checking its signature', async () => {
		const check = vi.fn().mockResolvedValue(undefined);
		const other = message({ TopicArn: 'arn:aws:sns:us-east-1:999999999999:someone-else' });
		expect(await verifySnsMessage(JSON.stringify(other), TOPIC, check)).toBeNull();
		expect(check).not.toHaveBeenCalled();
	});

	it('refuses bodies that are not an SNS message', async () => {
		const check = vi.fn().mockResolvedValue(undefined);
		expect(await verifySnsMessage('not json', TOPIC, check)).toBeNull();
		expect(await verifySnsMessage('null', TOPIC, check)).toBeNull();
		expect(await verifySnsMessage(JSON.stringify({ hello: 'world' }), TOPIC, check)).toBeNull();
		expect(
			await verifySnsMessage(JSON.stringify(message({ Type: 'Other' })), TOPIC, check)
		).toBeNull();
	});
});

describe('awsSnsSignatureCheck', () => {
	it('refuses a certificate hosted outside SNS in our region before fetching it', async () => {
		const check = awsSnsSignatureCheck('us-east-1');
		await expect(
			check(message({ SigningCertURL: 'https://sns.eu-west-1.amazonaws.com/cert.pem' }))
		).rejects.toThrow(/invalid domain/);
		await expect(
			check(message({ SigningCertURL: 'https://attacker.example/sns.us-east-1.amazonaws.com.pem' }))
		).rejects.toThrow(/invalid domain/);
	});
});

describe('trustedSubscribeUrl', () => {
	it('only trusts HTTPS SNS in our region', () => {
		expect(
			trustedSubscribeUrl(
				'https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription',
				'us-east-1'
			)
		).not.toBeNull();
		expect(trustedSubscribeUrl('http://sns.us-east-1.amazonaws.com/', 'us-east-1')).toBeNull();
		expect(trustedSubscribeUrl('https://sns.eu-west-1.amazonaws.com/', 'us-east-1')).toBeNull();
		expect(trustedSubscribeUrl('https://evil.example/', 'us-east-1')).toBeNull();
		expect(trustedSubscribeUrl('not a url', 'us-east-1')).toBeNull();
		expect(trustedSubscribeUrl(undefined, 'us-east-1')).toBeNull();
	});
});
