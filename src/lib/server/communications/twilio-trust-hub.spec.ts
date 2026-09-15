import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createTwilioTrustHubClient, TwilioTrustHubError } from './twilio-trust-hub';
import type { TwilioPlatformEnv } from './twilio';

const platform: TwilioPlatformEnv = {
	TWILIO_ACCOUNT_SID: 'AC00000000000000000000000000000001',
	TWILIO_AUTH_TOKEN: 'master-token',
	TWILIO_PROVISIONING_KEY_SID: 'SK00000000000000000000000000000001',
	TWILIO_PROVISIONING_KEY_SECRET: 'provisioning-secret'
};

const provisioningAuth = Buffer.from(
	`${platform.TWILIO_PROVISIONING_KEY_SID}:${platform.TWILIO_PROVISIONING_KEY_SECRET}`
).toString('base64');

const client = createTwilioTrustHubClient(platform);

function lastCall() {
	const [url, init] = vi.mocked(fetch).mock.calls.at(-1)!;
	return { url: String(url), init, params: new URLSearchParams((init?.body as string) ?? '') };
}

function expectProvisioningAuth(init: RequestInit | undefined) {
	expect((init?.headers as Record<string, string>).authorization).toBe(`Basic ${provisioningAuth}`);
}

describe('twilio-trust-hub adapter', () => {
	beforeEach(() => vi.stubGlobal('fetch', vi.fn()));
	afterEach(() => vi.unstubAllGlobals());

	it('createCustomerProfile POSTs to /v1/CustomerProfiles with the given policy', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'BU00000000000000000000000000000001', status: 'draft' }), {
				status: 201
			})
		);

		await expect(
			client.createCustomerProfile({
				friendlyName: 'Raad LTD',
				email: 'owner@raad.example',
				policySid: 'RNpolicy'
			})
		).resolves.toEqual({ sid: 'BU00000000000000000000000000000001', status: 'draft' });

		const { url, init, params } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/CustomerProfiles');
		expect(init).toMatchObject({ method: 'POST' });
		expectProvisioningAuth(init);
		expect(params.get('FriendlyName')).toBe('Raad LTD');
		expect(params.get('Email')).toBe('owner@raad.example');
		expect(params.get('PolicySid')).toBe('RNpolicy');
		expect(params.has('StatusCallback')).toBe(false);
	});

	it('createTrustProduct POSTs to /v1/TrustProducts', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'BU00000000000000000000000000000002', status: 'draft' }), {
				status: 201
			})
		);

		await client.createTrustProduct({
			friendlyName: 'Raad LTD A2P',
			email: 'owner@raad.example',
			statusCallback: 'https://app.example/webhook',
			policySid: 'RNa2p'
		});

		const { url, params } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/TrustProducts');
		expect(params.get('PolicySid')).toBe('RNa2p');
		expect(params.get('StatusCallback')).toBe('https://app.example/webhook');
	});

	it('createEndUser POSTs to /v1/EndUsers with JSON-encoded attributes', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'IT00000000000000000000000000000001' }), { status: 201 })
		);

		await client.createEndUser({
			friendlyName: 'Authorized Rep',
			type: 'authorized_representative',
			attributes: { job_position: 'Owner' }
		});

		const { url, params } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/EndUsers');
		expect(params.get('Type')).toBe('authorized_representative');
		expect(params.get('Attributes')).toBe(JSON.stringify({ job_position: 'Owner' }));
	});

	it('createAddress POSTs to the legacy 2010 Addresses resource under the platform account', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'AD00000000000000000000000000000001' }), { status: 201 })
		);

		await client.createAddress({
			customerName: 'Raad LTD',
			street: '123 Main St',
			city: 'Dhaka',
			region: 'Dhaka',
			postalCode: '1000',
			isoCountry: 'BD',
			friendlyName: 'HQ'
		});

		const { url, params } = lastCall();
		expect(url).toBe(
			`https://api.twilio.com/2010-04-01/Accounts/${platform.TWILIO_ACCOUNT_SID}/Addresses.json`
		);
		expect(params.get('IsoCountry')).toBe('BD');
		expect(params.has('StreetSecondary')).toBe(false);
	});

	it('createSupportingDocument POSTs to /v1/SupportingDocuments', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'RD00000000000000000000000000000001' }), { status: 201 })
		);

		await client.createSupportingDocument({
			friendlyName: 'Business Address',
			type: 'customer_profile_address',
			attributes: { address_sids: 'AD00000000000000000000000000000001' }
		});

		const { url } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/SupportingDocuments');
	});

	it('createCustomerProfileEntityAssignment attaches an object to a Customer Profile bundle', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'RA00000000000000000000000000000001' }), { status: 201 })
		);

		await expect(
			client.createCustomerProfileEntityAssignment({
				customerProfileSid: 'BUprofile',
				objectSid: 'ITenduser'
			})
		).resolves.toEqual({ sid: 'RA00000000000000000000000000000001', objectSid: 'ITenduser' });

		const { url, params } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/CustomerProfiles/BUprofile/EntityAssignments');
		expect(params.get('ObjectSid')).toBe('ITenduser');
	});

	it('createTrustProductEntityAssignment attaches an object to a Trust Product bundle', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: 'RA00000000000000000000000000000002' }), { status: 201 })
		);

		await client.createTrustProductEntityAssignment({
			trustProductSid: 'BUtrust',
			objectSid: 'ITenduser'
		});

		const { url, params } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/TrustProducts/BUtrust/EntityAssignments');
		expect(params.get('ObjectSid')).toBe('ITenduser');
	});

	it('evaluateCustomerProfile POSTs to Evaluations and parses pass/fail results', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({
					sid: 'EL00000000000000000000000000000001',
					status: 'noncompliant',
					results: [
						{ requirement_name: 'business_information', passed: true },
						{ friendly_name: 'address', passed: false, failure_reason: 'Missing postal code' }
					]
				}),
				{ status: 201 }
			)
		);

		await expect(
			client.evaluateCustomerProfile({ customerProfileSid: 'BUprofile', policySid: 'RNpolicy' })
		).resolves.toEqual({
			sid: 'EL00000000000000000000000000000001',
			status: 'noncompliant',
			results: [
				{ requirementName: 'business_information', passed: true, failureReason: null },
				{ requirementName: 'address', passed: false, failureReason: 'Missing postal code' }
			]
		});

		const { url, params } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/CustomerProfiles/BUprofile/Evaluations');
		expect(params.get('PolicySid')).toBe('RNpolicy');
	});

	it('evaluateTrustProduct POSTs to Evaluations under TrustProducts', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({
					sid: 'EL00000000000000000000000000000002',
					status: 'compliant',
					results: []
				}),
				{ status: 201 }
			)
		);

		await client.evaluateTrustProduct({ trustProductSid: 'BUtrust', policySid: 'RNa2p' });

		const { url } = lastCall();
		expect(url).toBe('https://trusthub.twilio.com/v1/TrustProducts/BUtrust/Evaluations');
	});

	it('submitCustomerProfileForReview POSTs Status=pending-review to the profile itself', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({ sid: 'BU00000000000000000000000000000001', status: 'pending-review' }),
				{ status: 200 }
			)
		);

		await client.submitCustomerProfileForReview('BU00000000000000000000000000000001');

		const { url, params } = lastCall();
		expect(url).toBe(
			'https://trusthub.twilio.com/v1/CustomerProfiles/BU00000000000000000000000000000001'
		);
		expect(params.get('Status')).toBe('pending-review');
	});

	it('submitTrustProductForReview POSTs Status=pending-review to the trust product itself', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({ sid: 'BU00000000000000000000000000000002', status: 'pending-review' }),
				{ status: 200 }
			)
		);

		await client.submitTrustProductForReview('BU00000000000000000000000000000002');

		const { url, params } = lastCall();
		expect(url).toBe(
			'https://trusthub.twilio.com/v1/TrustProducts/BU00000000000000000000000000000002'
		);
		expect(params.get('Status')).toBe('pending-review');
	});

	it('createBrandRegistration POSTs to messaging.twilio.com with both bundle SIDs and optional flags', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({ sid: 'BN00000000000000000000000000000001', status: 'PENDING' }),
				{ status: 201 }
			)
		);

		await expect(
			client.createBrandRegistration({
				customerProfileBundleSid: 'BUprofile',
				a2pProfileBundleSid: 'BUtrust',
				brandType: 'SOLE_PROPRIETOR',
				skipAutomaticSecVet: true
			})
		).resolves.toEqual({
			sid: 'BN00000000000000000000000000000001',
			status: 'PENDING',
			failureReason: null
		});

		const { url, params } = lastCall();
		expect(url).toBe('https://messaging.twilio.com/v1/a2p/BrandRegistrations');
		expect(params.get('CustomerProfileBundleSid')).toBe('BUprofile');
		expect(params.get('A2PProfileBundleSid')).toBe('BUtrust');
		expect(params.get('BrandType')).toBe('SOLE_PROPRIETOR');
		expect(params.get('SkipAutomaticSecVet')).toBe('true');
		expect(params.has('Mock')).toBe(false);
	});

	it('createBrandRegistration surfaces a joined failure_reason/errors summary on a failed Brand', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({
					sid: 'BN00000000000000000000000000000002',
					status: 'FAILED',
					errors: [{ message: 'Ineligible business information' }, { message: 'Tax ID mismatch' }]
				}),
				{ status: 201 }
			)
		);

		await expect(
			client.createBrandRegistration({
				customerProfileBundleSid: 'BUprofile',
				a2pProfileBundleSid: 'BUtrust'
			})
		).resolves.toEqual({
			sid: 'BN00000000000000000000000000000002',
			status: 'FAILED',
			failureReason: 'Ineligible business information; Tax ID mismatch'
		});
	});

	it('fetchBrandRegistration GETs the Brand by SID with no body', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({ sid: 'BN00000000000000000000000000000001', status: 'APPROVED' }),
				{ status: 200 }
			)
		);

		await expect(
			client.fetchBrandRegistration('BN00000000000000000000000000000001')
		).resolves.toEqual({
			sid: 'BN00000000000000000000000000000001',
			status: 'APPROVED',
			failureReason: null
		});

		const { url, init } = lastCall();
		expect(url).toBe(
			'https://messaging.twilio.com/v1/a2p/BrandRegistrations/BN00000000000000000000000000000001'
		);
		expect(init).toMatchObject({ method: 'GET' });
		expect(init?.body).toBeUndefined();
	});

	it('createCampaign POSTs the Usa2p resource with MessageSamples repeated per item', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({ sid: 'QE00000000000000000000000000000001', campaign_status: 'PENDING' }),
				{ status: 201 }
			)
		);

		await expect(
			client.createCampaign({
				messagingServiceSid: 'MGservice',
				brandRegistrationSid: 'BN00000000000000000000000000000001',
				description: 'A'.repeat(40),
				messageFlow: 'B'.repeat(40),
				messageSamples: ['Sample one is long enough.', 'Sample two is long enough too.'],
				usAppToPersonUsecase: 'CUSTOMER_CARE',
				hasEmbeddedLinks: false,
				hasEmbeddedPhone: true
			})
		).resolves.toEqual({
			sid: 'QE00000000000000000000000000000001',
			status: 'PENDING',
			failureReason: null
		});

		const { url, params } = lastCall();
		expect(url).toBe('https://messaging.twilio.com/v1/Services/MGservice/Compliance/Usa2p');
		expect(params.get('BrandRegistrationSid')).toBe('BN00000000000000000000000000000001');
		expect(params.getAll('MessageSamples')).toEqual([
			'Sample one is long enough.',
			'Sample two is long enough too.'
		]);
		expect(params.get('HasEmbeddedLinks')).toBe('false');
		expect(params.get('HasEmbeddedPhone')).toBe('true');
	});

	it('fetchCampaign GETs the Usa2p resource under the Messaging Service by Campaign SID', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({ sid: 'QE00000000000000000000000000000001', campaign_status: 'VERIFIED' }),
				{ status: 200 }
			)
		);

		await expect(
			client.fetchCampaign({
				messagingServiceSid: 'MGservice',
				campaignSid: 'QE00000000000000000000000000000001'
			})
		).resolves.toEqual({
			sid: 'QE00000000000000000000000000000001',
			status: 'VERIFIED',
			failureReason: null
		});

		const { url, init } = lastCall();
		expect(url).toBe(
			'https://messaging.twilio.com/v1/Services/MGservice/Compliance/Usa2p/QE00000000000000000000000000000001'
		);
		expect(init).toMatchObject({ method: 'GET' });
	});

	describe('error classification (shared across every call, exercised once via createCustomerProfile)', () => {
		const call = () =>
			client.createCustomerProfile({
				friendlyName: 'Raad LTD',
				email: 'owner@raad.example',
				policySid: 'RNpolicy'
			});

		it('classifies a 429 as retryable and keeps the provider code', async () => {
			vi.mocked(fetch).mockResolvedValueOnce(
				new Response(JSON.stringify({ code: 20429 }), { status: 429 })
			);

			await expect(call()).rejects.toMatchObject({
				retryable: true,
				code: 'twilio_trust_hub_rejected',
				providerCode: '20429'
			});
		});

		it('classifies a 5xx as retryable', async () => {
			vi.mocked(fetch).mockResolvedValueOnce(new Response('bad gateway', { status: 502 }));

			await expect(call()).rejects.toMatchObject({ retryable: true, status: 502 });
		});

		it('classifies a definite 4xx as not retryable and needing operator review', async () => {
			vi.mocked(fetch).mockResolvedValueOnce(
				new Response(JSON.stringify({ code: 21608, message: 'invalid email' }), { status: 400 })
			);

			await expect(call()).rejects.toMatchObject({
				retryable: false,
				status: 400,
				providerCode: '21608'
			});
		});

		it('treats a network/timeout failure as an unknown, retryable outcome without leaking the raw error', async () => {
			vi.mocked(fetch).mockRejectedValueOnce(new Error('socket hang up: Basic dHJ1c3Q6c2VjcmV0'));

			const rejection = call();
			await expect(rejection).rejects.toMatchObject({
				retryable: true,
				status: null,
				code: 'twilio_trust_hub_unknown'
			});
			await expect(rejection).rejects.not.toThrow(/dHJ1c3Q6c2VjcmV0/);
		});

		it('treats a 2xx missing a usable SID as a non-retryable adapter-level failure', async () => {
			vi.mocked(fetch).mockResolvedValueOnce(
				new Response(JSON.stringify({ status: 'draft' }), { status: 201 })
			);

			await expect(call()).rejects.toMatchObject({
				retryable: false,
				code: 'twilio_trust_hub_missing_profile_sid'
			});
		});

		it('is a TwilioTrustHubError for every provider failure', async () => {
			vi.mocked(fetch).mockResolvedValueOnce(new Response('nope', { status: 401 }));
			await expect(call()).rejects.toBeInstanceOf(TwilioTrustHubError);
		});
	});
});
