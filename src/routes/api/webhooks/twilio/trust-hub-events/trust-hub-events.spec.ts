import { beforeEach, describe, expect, it, vi } from 'vitest';
import { getServerEnv } from '$lib/server/env';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createSupabaseTrustHubSubmissionStore } from '$lib/server/communications/trust-hub-submission-store';
import { createSupabaseTrustHubStatusTriggerStore } from '$lib/server/communications/trust-hub-status-trigger-store';
import { syncTrustHubRegistrationStatus } from '$lib/server/communications/trust-hub-submission';
import {
	TwilioTrustHubError,
	createTwilioTrustHubClient
} from '$lib/server/communications/twilio-trust-hub';

vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/trust-hub-submission-store', () => ({
	createSupabaseTrustHubSubmissionStore: vi.fn()
}));
vi.mock('$lib/server/communications/twilio-trust-hub', async (importOriginal) => {
	const actual =
		await importOriginal<typeof import('$lib/server/communications/twilio-trust-hub')>();
	return { ...actual, createTwilioTrustHubClient: vi.fn() };
});
vi.mock('$lib/server/communications/trust-hub-status-trigger-store', () => ({
	createSupabaseTrustHubStatusTriggerStore: vi.fn()
}));
vi.mock('$lib/server/communications/trust-hub-submission', async (importOriginal) => {
	const actual =
		await importOriginal<typeof import('$lib/server/communications/trust-hub-submission')>();
	return { ...actual, syncTrustHubRegistrationStatus: vi.fn() };
});

import { POST, _TRUST_HUB_EVENTS_WEBHOOK_USERNAME } from './+server';

const SECRET = 'a-long-random-trust-hub-webhook-secret-value';
const URL = 'http://localhost/api/webhooks/twilio/trust-hub-events';

const mockedServerEnv = vi.mocked(getServerEnv);
const mockedFindByResourceSid = vi.fn();
const mockedSync = vi.mocked(syncTrustHubRegistrationStatus);

function basicAuthHeader(username: string, password: string) {
	return `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`;
}

function requestWith(body: unknown, authorization?: string) {
	return {
		request: new Request(URL, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				...(authorization ? { authorization } : {})
			},
			body: JSON.stringify(body)
		})
	} as Parameters<typeof POST>[0];
}

const BRAND_EVENT = {
	type: 'com.twilio.messaging.compliance.brand-registration.brand-verified',
	data: { brandsid: 'BN00000000000000000000000000000001' }
};
const CAMPAIGN_EVENT = {
	type: 'com.twilio.messaging.compliance.campaign-registration.campaign-approved',
	data: JSON.stringify({ campaignsid: 'CM00000000000000000000000000000001' })
};

describe('trust-hub-events webhook route', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedServerEnv.mockReturnValue({ TRUST_HUB_EVENTS_WEBHOOK_SECRET: SECRET } as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({} as never);
		vi.mocked(createSupabaseTrustHubSubmissionStore).mockReturnValue({} as never);
		vi.mocked(createTwilioTrustHubClient).mockReturnValue({} as never);
		vi.mocked(createSupabaseTrustHubStatusTriggerStore).mockReturnValue({
			findRegistrationIdByResourceSid: mockedFindByResourceSid,
			listRegistrationIdsPendingSync: vi.fn()
		});
	});

	it('rejects a request with no Authorization header', async () => {
		const response = await POST(requestWith([BRAND_EVENT]));
		expect(response.status).toBe(403);
		expect(mockedSync).not.toHaveBeenCalled();
	});

	it('rejects the wrong Basic auth password', async () => {
		const response = await POST(
			requestWith(
				[BRAND_EVENT],
				basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, 'wrong-secret')
			)
		);
		expect(response.status).toBe(403);
	});

	it('rejects when the secret is not configured at all', async () => {
		mockedServerEnv.mockReturnValue({ TRUST_HUB_EVENTS_WEBHOOK_SECRET: undefined } as never);
		const response = await POST(
			requestWith([BRAND_EVENT], basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);
		expect(response.status).toBe(403);
	});

	it('rejects a body that is not a JSON array', async () => {
		const response = await POST(
			requestWith({ not: 'an array' }, basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);
		expect(response.status).toBe(403);
	});

	it('looks up the registration by brandsid and syncs it for a Brand event', async () => {
		mockedFindByResourceSid.mockResolvedValue('registration-1');
		mockedSync.mockResolvedValue({
			registrationId: 'registration-1',
			brandStatus: 'APPROVED',
			campaignStatus: null,
			registrationStatus: 'under_review'
		});

		const response = await POST(
			requestWith([BRAND_EVENT], basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);

		expect(response.status).toBe(204);
		expect(mockedFindByResourceSid).toHaveBeenCalledWith(
			'brand_registration',
			'BN00000000000000000000000000000001'
		);
		expect(mockedSync).toHaveBeenCalledWith(expect.anything(), {
			registrationId: 'registration-1'
		});
	});

	it('parses a stringified data field and syncs a Campaign event', async () => {
		mockedFindByResourceSid.mockResolvedValue('registration-2');
		mockedSync.mockResolvedValue({
			registrationId: 'registration-2',
			brandStatus: 'APPROVED',
			campaignStatus: 'VERIFIED',
			registrationStatus: 'approved'
		});

		const response = await POST(
			requestWith([CAMPAIGN_EVENT], basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);

		expect(response.status).toBe(204);
		expect(mockedFindByResourceSid).toHaveBeenCalledWith(
			'campaign',
			'CM00000000000000000000000000000001'
		);
	});

	it('accepts and ignores an event for an unknown SID without calling sync', async () => {
		mockedFindByResourceSid.mockResolvedValue(null);

		const response = await POST(
			requestWith([BRAND_EVENT], basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);

		expect(response.status).toBe(204);
		expect(mockedSync).not.toHaveBeenCalled();
	});

	it('accepts and ignores an event type it does not wire up yet', async () => {
		const response = await POST(
			requestWith(
				[{ type: 'com.twilio.messaging.compliance.number-registration.pending', data: {} }],
				basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET)
			)
		);

		expect(response.status).toBe(204);
		expect(mockedFindByResourceSid).not.toHaveBeenCalled();
	});

	it('asks Twilio to redeliver when the sync fails with a retryable transport error', async () => {
		mockedFindByResourceSid.mockResolvedValue('registration-3');
		mockedSync.mockRejectedValue(new TwilioTrustHubError('timeout', null, 'network_error', true));

		const response = await POST(
			requestWith([BRAND_EVENT], basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);

		expect(response.status).toBe(500);
	});

	it('accepts the event when the sync fails with a non-retryable error', async () => {
		mockedFindByResourceSid.mockResolvedValue('registration-4');
		mockedSync.mockRejectedValue(new Error('no submission on file'));

		const response = await POST(
			requestWith([BRAND_EVENT], basicAuthHeader(_TRUST_HUB_EVENTS_WEBHOOK_USERNAME, SECRET))
		);

		expect(response.status).toBe(204);
	});
});
