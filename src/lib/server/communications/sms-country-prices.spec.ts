import { describe, expect, it } from 'vitest';
import { twilioPriceRows } from './sms-country-prices';

describe('twilioPriceRows', () => {
	it('records the dearest carrier for each sender type and the monthly number cost', () => {
		const rows = twilioPriceRows(
			'GB',
			{
				countryCode: 'GB',
				currency: 'USD',
				inbound: { mobile: '0.0075' },
				outbound: {
					mobile: { min: '0.0400', max: '0.0524' },
					alphanumeric: { min: '0.05', max: '0.06' }
				}
			},
			{ countryCode: 'GB', currency: 'USD', monthly: { mobile: '1.15' } }
		);

		expect(rows).toEqual([
			{
				country_code: 'GB',
				kind: 'segment',
				number_type: 'mobile',
				currency_code: 'USD',
				cost_major: 0.0524
			},
			{
				country_code: 'GB',
				kind: 'segment',
				number_type: 'alphanumeric',
				currency_code: 'USD',
				cost_major: 0.06
			},
			{
				country_code: 'GB',
				kind: 'number_month',
				number_type: 'mobile',
				currency_code: 'USD',
				cost_major: 1.15
			}
		]);
	});

	it('returns nothing when Twilio has no prices for the country', () => {
		expect(twilioPriceRows('XX', null, null)).toEqual([]);
	});

	it('keeps message prices when the country has no numbers to rent', () => {
		const rows = twilioPriceRows(
			'BD',
			{
				countryCode: 'BD',
				currency: 'USD',
				inbound: {},
				outbound: { mobile: { min: '0.3', max: '0.35' } }
			},
			null
		);
		expect(rows).toEqual([
			{
				country_code: 'BD',
				kind: 'segment',
				number_type: 'mobile',
				currency_code: 'USD',
				cost_major: 0.35
			}
		]);
	});
});
