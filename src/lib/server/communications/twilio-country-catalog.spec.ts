import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
	createTwilioCountryCatalogClient,
	normalizeNumberType,
	parseField,
	TwilioCatalogError
} from './twilio-country-catalog';
import type { TwilioPlatformEnv } from './twilio';

// Response bodies below are trimmed copies of live read-only Twilio replies (2026-10-22).

const platform: TwilioPlatformEnv = {
	TWILIO_ACCOUNT_SID: 'AC00000000000000000000000000000001',
	TWILIO_AUTH_TOKEN: 'master-token',
	TWILIO_PROVISIONING_KEY_SID: 'SK00000000000000000000000000000001',
	TWILIO_PROVISIONING_KEY_SECRET: 'provisioning-secret'
};
const accountPath = `/2010-04-01/Accounts/${platform.TWILIO_ACCOUNT_SID}`;
const provisioningAuth = `Basic ${Buffer.from(
	`${platform.TWILIO_PROVISIONING_KEY_SID}:${platform.TWILIO_PROVISIONING_KEY_SECRET}`
).toString('base64')}`;

const client = createTwilioCountryCatalogClient(platform);

function reply(body: unknown, status = 200) {
	vi.mocked(fetch).mockResolvedValueOnce(new Response(JSON.stringify(body), { status }));
}

function call(index = -1) {
	const [url, init] = vi.mocked(fetch).mock.calls.at(index)!;
	return { url: new URL(String(url)), init };
}

describe('twilio-country-catalog adapter', () => {
	beforeEach(() => vi.stubGlobal('fetch', vi.fn()));
	afterEach(() => vi.unstubAllGlobals());

	describe('listCountries', () => {
		it('lists in-stock countries with their number types, sorted by name, using the platform key', async () => {
			reply({
				countries: [
					{
						country: 'United Kingdom',
						country_code: 'GB',
						beta: false,
						subresource_uris: {
							local: `${accountPath}/AvailablePhoneNumbers/GB/Local.json`,
							mobile: `${accountPath}/AvailablePhoneNumbers/GB/Mobile.json`,
							toll_free: `${accountPath}/AvailablePhoneNumbers/GB/TollFree.json`
						}
					},
					{
						country: 'Brazil',
						country_code: 'BR',
						beta: false,
						subresource_uris: { local: `${accountPath}/AvailablePhoneNumbers/BR/Local.json` }
					},
					// A country offering only types this build does not know is left out.
					{ country: 'Nowhere', country_code: 'NW', subresource_uris: { voip: '/x' } }
				]
			});

			await expect(client.listCountries()).resolves.toEqual([
				{ countryCode: 'BR', name: 'Brazil', beta: false, numberTypes: ['local'] },
				{
					countryCode: 'GB',
					name: 'United Kingdom',
					beta: false,
					numberTypes: ['local', 'mobile', 'toll_free']
				}
			]);

			const { url, init } = call();
			expect(url.origin + url.pathname).toBe(
				`https://api.twilio.com${accountPath}/AvailablePhoneNumbers.json`
			);
			expect((init?.headers as Record<string, string>).authorization).toBe(provisioningAuth);
		});

		it('follows a relative next page on the same host', async () => {
			reply({
				countries: [{ country: 'Spain', country_code: 'ES', subresource_uris: { local: '/a' } }],
				next_page_uri: `${accountPath}/AvailablePhoneNumbers.json?Page=1`
			});
			reply({
				countries: [{ country: 'France', country_code: 'FR', subresource_uris: { mobile: '/b' } }],
				next_page_uri: null
			});

			const countries = await client.listCountries();
			expect(countries.map((c) => c.countryCode)).toEqual(['FR', 'ES']);
			expect(call(1).url.searchParams.get('Page')).toBe('1');
		});
	});

	describe('searchNumbers', () => {
		it('passes the filters and reads both capability spellings', async () => {
			reply({
				available_phone_numbers: [
					{
						phone_number: '+4915888361757',
						friendly_name: '+4915888361757',
						iso_country: 'DE',
						capabilities: { MMS: false, SMS: true, voice: true },
						address_requirements: 'local',
						beta: false,
						locality: null,
						region: null,
						postal_code: null
					},
					{
						phone_number: '+18449002989',
						friendly_name: '(844) 900-2989',
						iso_country: 'US',
						capabilities: { mms: true, sms: true, voice: false },
						address_requirements: 'none'
					},
					{ phone_number: 'not-a-number', iso_country: 'DE' }
				]
			});

			const numbers = await client.searchNumbers({
				countryCode: 'DE',
				numberType: 'mobile',
				sms: true,
				contains: '1588',
				limit: 2
			});

			expect(numbers).toHaveLength(2);
			expect(numbers[0]).toMatchObject({
				phoneNumber: '+4915888361757',
				numberType: 'mobile',
				capabilities: { sms: true, mms: false, voice: true },
				addressRequirement: 'local'
			});
			expect(numbers[1].capabilities).toEqual({ sms: true, mms: true, voice: false });

			const { url } = call();
			expect(url.pathname).toBe(`${accountPath}/AvailablePhoneNumbers/DE/Mobile.json`);
			expect(url.searchParams.get('SmsEnabled')).toBe('true');
			expect(url.searchParams.has('MmsEnabled')).toBe(false);
			expect(url.searchParams.get('Contains')).toBe('1588');
			expect(url.searchParams.get('PageSize')).toBe('2');
		});

		it('uses the TollFree path for toll-free numbers', async () => {
			reply({ available_phone_numbers: [] });
			await client.searchNumbers({ countryCode: 'US', numberType: 'toll_free' });
			expect(call().url.pathname).toBe(`${accountPath}/AvailablePhoneNumbers/US/TollFree.json`);
		});

		it('treats an unknown address rule as needing an address', async () => {
			reply({
				available_phone_numbers: [
					{ phone_number: '+12025550100', iso_country: 'US', address_requirements: 'weird' }
				]
			});
			const [number] = await client.searchNumbers({ countryCode: 'US', numberType: 'local' });
			expect(number.addressRequirement).toBe('any');
		});

		it('returns no numbers when Twilio has no inventory (404)', async () => {
			reply({ code: 20404, message: 'not found' }, 404);
			await expect(
				client.searchNumbers({ countryCode: 'NZ', numberType: 'mobile' })
			).resolves.toEqual([]);
		});

		it('reports a provider outage as a retryable error', async () => {
			reply({ code: 20500 }, 503);
			await expect(
				client.searchNumbers({ countryCode: 'GB', numberType: 'local' })
			).rejects.toMatchObject({ retryable: true, status: 503 });
		});

		it('reports a network failure without echoing the request', async () => {
			vi.mocked(fetch).mockRejectedValueOnce(new Error(`boom ${provisioningAuth}`));
			const error = await client
				.searchNumbers({ countryCode: 'GB', numberType: 'local' })
				.catch((e: unknown) => e);
			expect(error).toBeInstanceOf(TwilioCatalogError);
			expect((error as TwilioCatalogError).retryable).toBe(true);
			expect((error as Error).message).not.toContain('Basic');
		});

		it('refuses unsafe input before calling Twilio', async () => {
			await expect(
				client.searchNumbers({ countryCode: 'gb/../x', numberType: 'local' })
			).rejects.toMatchObject({ code: 'twilio_catalog_invalid_input' });
			await expect(
				client.searchNumbers({ countryCode: 'GB', numberType: 'local', contains: '1&x=2' })
			).rejects.toMatchObject({ code: 'twilio_catalog_invalid_input' });
			expect(fetch).not.toHaveBeenCalled();
		});
	});

	describe('getRegulation', () => {
		const gbMobileBusiness = {
			sid: 'RNb257214105d3b9526d5f80359b863452',
			friendly_name: 'United Kingdom: Mobile - Business',
			iso_country: 'GB',
			number_type: 'mobile',
			end_user_type: 'business',
			requirements: {
				end_user: [
					{
						name: 'Business',
						type: 'business',
						requirement_name: 'business_info',
						fields: ['business_name', 'business_registration_identifier', 'email', 'comments'],
						detailed_fields: [
							{
								machine_name: 'business_name',
								friendly_name: 'Business Name',
								description: '',
								constraint: "business['business_name'] != null"
							},
							{
								machine_name: 'business_registration_identifier',
								friendly_name: 'Registration Authority',
								description: 'Choose one of the following values: UK:CRN, US:EIN ',
								constraint:
									"business['business_registration_identifier'] =~ '^(UK:CRN|US:EIN|CA:CBN|AU:ACN|OTHER)$'"
							},
							{
								machine_name: 'email',
								friendly_name: "Authorized Representative's Work Email",
								description: 'Domain should match business name or website',
								constraint: "business['email'] =~ '^\\S+@\\S+\\.\\S+$'"
							},
							{
								machine_name: 'comments',
								friendly_name: 'Comments (Optional)',
								description: 'Optional',
								constraint: ''
							}
						]
					}
				],
				supporting_document: [
					[
						{
							name: 'Proof of Address',
							requirement_name: 'business_address',
							description: 'May be anywhere in the world;  a PO Box is not acceptable.',
							type: 'document',
							accepted_documents: [
								{
									name: 'Business address',
									type: 'business_address',
									fields: ['address_sids'],
									detailed_fields: [
										{
											machine_name: 'address_sids',
											friendly_name: 'Business Address sid',
											description: '',
											constraint: "business_address['address_sids'] != null"
										}
									]
								}
							]
						}
					]
				]
			}
		};

		it('reads the live requirements into form-ready fields', async () => {
			reply({ results: [gbMobileBusiness], meta: { next_page_url: null } });

			const regulation = await client.getRegulation({
				countryCode: 'GB',
				numberType: 'mobile',
				endUserType: 'business'
			});

			expect(regulation).toMatchObject({
				regulationSid: 'RNb257214105d3b9526d5f80359b863452',
				countryCode: 'GB',
				numberType: 'mobile',
				endUserType: 'business'
			});
			const fields = regulation!.endUser[0].fields;
			expect(fields.map((f) => [f.name, f.required])).toEqual([
				['business_name', true],
				['business_registration_identifier', true],
				['email', true],
				['comments', false]
			]);
			expect(fields[1].choices).toEqual(['UK:CRN', 'US:EIN', 'CA:CBN', 'AU:ACN', 'OTHER']);
			expect(fields[1].pattern).toBeNull();
			expect(fields[2].pattern).toBe('^\\S+@\\S+\\.\\S+$');
			expect(new RegExp(fields[2].pattern!).test('owner@raad.example')).toBe(true);
			expect(regulation!.documents).toEqual([
				expect.objectContaining({
					requirementName: 'business_address',
					label: 'Proof of Address',
					acceptedDocuments: [expect.objectContaining({ documentType: 'business_address' })]
				})
			]);

			const { url } = call();
			expect(url.origin + url.pathname).toBe(
				'https://numbers.twilio.com/v2/RegulatoryCompliance/Regulations'
			);
			expect(url.searchParams.get('IsoCountry')).toBe('GB');
			expect(url.searchParams.get('NumberType')).toBe('mobile');
			expect(url.searchParams.get('EndUserType')).toBe('business');
			expect(url.searchParams.get('IncludeConstraints')).toBe('true');
		});

		it('asks for toll-free paperwork with Twilio’s hyphenated spelling', async () => {
			reply({ results: [], meta: { next_page_url: null } });
			await expect(
				client.getRegulation({
					countryCode: 'DE',
					numberType: 'toll_free',
					endUserType: 'business'
				})
			).resolves.toBeNull();
			expect(call().url.searchParams.get('NumberType')).toBe('toll-free');
		});

		it('returns a regulation with no requirements when the country asks for none (US)', async () => {
			reply({
				results: [
					{
						sid: 'RN00000000000000000000000000000001',
						friendly_name: 'United States: Local - Business',
						number_type: 'local',
						end_user_type: 'business',
						requirements: { end_user: [], supporting_document: [] }
					}
				],
				meta: { next_page_url: null }
			});
			const regulation = await client.getRegulation({
				countryCode: 'US',
				numberType: 'local',
				endUserType: 'business'
			});
			expect(regulation).toMatchObject({ endUser: [], documents: [] });
		});

		it('never follows a next page to another host', async () => {
			reply({ results: [], meta: { next_page_url: 'https://evil.example/v2/steal?Page=1' } });
			await client.getRegulation({
				countryCode: 'GB',
				numberType: 'local',
				endUserType: 'business'
			});
			expect(fetch).toHaveBeenCalledTimes(1);
		});
	});

	describe('prices', () => {
		it('reads monthly number prices per type as exact decimals', async () => {
			reply({
				iso_country: 'GB',
				price_unit: 'USD',
				phone_number_prices: [
					{ number_type: 'local', base_price: '1.15', current_price: '1.15' },
					{ number_type: 'mobile', base_price: '2.50', current_price: '2.50' },
					{ number_type: 'toll free', base_price: '2.70', current_price: '2.60' }
				]
			});
			await expect(client.getNumberPrices('GB')).resolves.toEqual({
				countryCode: 'GB',
				currency: 'USD',
				monthly: { local: '1.15', mobile: '2.50', toll_free: '2.60' }
			});
			expect(call().url.href).toBe('https://pricing.twilio.com/v1/PhoneNumbers/Countries/GB');
		});

		it('reads inbound prices and the outbound range across carriers', async () => {
			reply({
				iso_country: 'GB',
				price_unit: 'usd',
				inbound_sms_prices: [
					{ number_type: 'local', current_price: '0.0075' },
					{ number_type: 'shortcode', current_price: '0.0075' }
				],
				outbound_sms_prices: [
					{
						carrier: 'Other',
						prices: [
							{ number_type: 'mobile', current_price: '0.056' },
							{ number_type: 'shortcode', current_price: '0.0524' }
						]
					},
					{ carrier: 'Vodafone', prices: [{ number_type: 'mobile', current_price: '0.0412' }] }
				]
			});
			await expect(client.getMessagePrices('GB')).resolves.toEqual({
				countryCode: 'GB',
				currency: 'USD',
				inbound: { local: '0.0075', short_code: '0.0075' },
				outbound: {
					mobile: { min: '0.0412', max: '0.056' },
					short_code: { min: '0.0524', max: '0.0524' }
				}
			});
		});

		it('returns null when Twilio publishes no prices for the country', async () => {
			reply({ code: 20404 }, 404);
			await expect(client.getMessagePrices('AQ')).resolves.toBeNull();
		});
	});
});

describe('parseField', () => {
	it('reads a must-match document field', () => {
		expect(
			parseField({
				machine_name: 'business_name',
				friendly_name: 'Business Name',
				constraint:
					"trade_license['business_name'] != null && trade_license['business_name'] == business['business_name']"
			})
		).toMatchObject({ required: true, mustMatch: 'business_name', pattern: null, choices: null });
	});

	it('keeps a phone pattern as a pattern, not choices', () => {
		const field = parseField({
			machine_name: 'phone_number',
			constraint: "business['phone_number'] =~ '^\\+[1-9]\\d{1,14}$'"
		});
		expect(field.choices).toBeNull();
		expect(new RegExp(field.pattern!).test('+447863765088')).toBe(true);
		expect(field.label).toBe('phone_number');
	});
});

describe('normalizeNumberType', () => {
	it('maps every Twilio spelling to one vocabulary', () => {
		expect(['toll free', 'toll-free', 'toll_free', 'TollFree'].map(normalizeNumberType)).toEqual([
			'toll_free',
			'toll_free',
			'toll_free',
			'toll_free'
		]);
		expect(normalizeNumberType('shortcode')).toBe('short_code');
		expect(normalizeNumberType('voip')).toBeNull();
	});
});
