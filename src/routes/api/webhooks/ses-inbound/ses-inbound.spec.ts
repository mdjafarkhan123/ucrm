import { beforeEach, describe, expect, it, vi } from 'vitest';

const wake = vi.fn();
const verify = vi.fn();

vi.mock('$lib/server/communications/ses-env', () => ({
	getSesEnv: () => ({ AWS_SES_REGION: 'us-east-1', accountId: '123456789012' }),
	sesInboundTopicArn: () => 'arn:aws:sns:us-east-1:123456789012:ucrm-ses-inbound'
}));
vi.mock('$lib/server/communications/sns-webhook', async (importOriginal) => {
	const actual = await importOriginal<typeof import('$lib/server/communications/sns-webhook')>();
	return { ...actual, verifySnsMessage: (...args: unknown[]) => verify(...args) };
});
vi.mock('$lib/server/communications/ses-inbound-worker', () => ({
	runMonitoredSesInboundWake: (...args: unknown[]) => wake(...args)
}));

const { POST } = await import('./+server');

function post() {
	const request = new Request('https://app.example/api/webhooks/ses-inbound', {
		method: 'POST',
		headers: { 'content-type': 'text/plain; charset=UTF-8' },
		body: '{}'
	});
	return POST({ request } as Parameters<typeof POST>[0]);
}

const fetchMock = vi.fn();

beforeEach(() => {
	wake.mockReset().mockResolvedValue({ outcome: 'idle' });
	verify.mockReset();
	fetchMock.mockReset();
	vi.stubGlobal('fetch', fetchMock);
});

describe('POST /api/webhooks/ses-inbound', () => {
	it('refuses anything not provably from our topic and never wakes the drain', async () => {
		verify.mockResolvedValue(null);
		const response = await post();
		expect(response.status).toBe(403);
		expect(wake).not.toHaveBeenCalled();
	});

	it('answers a notification at once and wakes the drain', async () => {
		verify.mockResolvedValue({ Type: 'Notification', MessageId: 'm', TopicArn: 't' });
		const response = await post();
		expect(response.status).toBe(200);
		expect(wake).toHaveBeenCalledOnce();
	});

	it('still answers 200 when the wake fails, leaving the message for the cron', async () => {
		verify.mockResolvedValue({ Type: 'Notification', MessageId: 'm', TopicArn: 't' });
		const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
		wake.mockRejectedValue(new Error('lease rpc down'));
		const response = await post();
		await Promise.resolve();
		expect(response.status).toBe(200);
		logged.mockRestore();
	});

	it('confirms a subscription only through SNS in our region', async () => {
		verify.mockResolvedValue({
			Type: 'SubscriptionConfirmation',
			MessageId: 'm',
			TopicArn: 't',
			SubscribeURL: 'https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=x'
		});
		fetchMock.mockResolvedValue(new Response('ok', { status: 200 }));
		expect((await post()).status).toBe(200);
		expect(String(fetchMock.mock.calls[0][0])).toContain('sns.us-east-1.amazonaws.com');
		expect(wake).not.toHaveBeenCalled();
	});

	it('never fetches a subscribe URL pointing elsewhere', async () => {
		verify.mockResolvedValue({
			Type: 'SubscriptionConfirmation',
			MessageId: 'm',
			TopicArn: 't',
			SubscribeURL: 'https://internal.example/admin'
		});
		expect((await post()).status).toBe(403);
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('asks SNS to resend when the confirmation call fails', async () => {
		verify.mockResolvedValue({
			Type: 'SubscriptionConfirmation',
			MessageId: 'm',
			TopicArn: 't',
			SubscribeURL: 'https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=x'
		});
		fetchMock.mockRejectedValue(new Error('network'));
		expect((await post()).status).toBe(502);
	});
});
