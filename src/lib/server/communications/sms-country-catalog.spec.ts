import { describe, expect, it, vi } from 'vitest';
import { createSmsCountryCatalog } from './sms-country-catalog';
import type {
	AvailableNumber,
	NumberSearchInput,
	TwilioCountryCatalogClient
} from './twilio-country-catalog';

function number(
	countryCode: string,
	capabilities: AvailableNumber['capabilities'],
	addressRequirement: AvailableNumber['addressRequirement'] = 'none'
): AvailableNumber {
	return {
		phoneNumber: '+447863765088',
		friendlyName: '+447863765088',
		countryCode,
		numberType: 'mobile',
		locality: null,
		region: null,
		postalCode: null,
		capabilities,
		addressRequirement,
		beta: false
	};
}

function fakeClient(overrides: Partial<TwilioCountryCatalogClient> = {}) {
	const client: TwilioCountryCatalogClient = {
		listCountries: vi.fn(async () => [
			{ countryCode: 'GB', name: 'United Kingdom', beta: false, numberTypes: ['local', 'mobile'] },
			{ countryCode: 'BR', name: 'Brazil', beta: false, numberTypes: ['local'] }
		]),
		searchNumbers: vi.fn(async () => []),
		getRegulation: vi.fn(async () => null),
		getNumberPrices: vi.fn(async (countryCode: string) => ({
			countryCode,
			currency: 'USD',
			monthly: { local: '1.15' }
		})),
		getMessagePrices: vi.fn(async () => null),
		...overrides
	};
	return client;
}

describe('sms country catalog', () => {
	it('serves repeat questions from the cache until it expires', async () => {
		let clock = 0;
		const client = fakeClient();
		const catalog = createSmsCountryCatalog({ client, ttlMs: 1000, now: () => clock });

		await catalog.getNumberPrices('GB');
		await catalog.getNumberPrices('GB');
		await catalog.getNumberPrices('DE');
		expect(client.getNumberPrices).toHaveBeenCalledTimes(2);

		clock = 1001;
		await catalog.getNumberPrices('GB');
		expect(client.getNumberPrices).toHaveBeenCalledTimes(3);
	});

	it('shares one in-flight request between concurrent callers', async () => {
		const client = fakeClient();
		const catalog = createSmsCountryCatalog({ client });
		await Promise.all([catalog.listCountries(), catalog.listCountries(), catalog.listCountries()]);
		expect(client.listCountries).toHaveBeenCalledTimes(1);
	});

	it('never caches a failure, so the next call retries Twilio', async () => {
		const getMessagePrices = vi
			.fn<TwilioCountryCatalogClient['getMessagePrices']>()
			.mockRejectedValueOnce(new Error('outage'))
			.mockResolvedValueOnce(null);
		const catalog = createSmsCountryCatalog({ client: fakeClient({ getMessagePrices }) });

		await expect(catalog.getMessagePrices('GB')).rejects.toThrow('outage');
		await expect(catalog.getMessagePrices('GB')).resolves.toBeNull();
		expect(getMessagePrices).toHaveBeenCalledTimes(2);
	});

	it('never caches a number search, since stock changes by the minute', async () => {
		const client = fakeClient();
		const catalog = createSmsCountryCatalog({ client });
		const search: NumberSearchInput = { countryCode: 'GB', numberType: 'local' };
		await catalog.searchNumbers(search);
		await catalog.searchNumbers(search);
		expect(client.searchNumbers).toHaveBeenCalledTimes(2);
	});

	it('clear() forgets every cached answer', async () => {
		const client = fakeClient();
		const catalog = createSmsCountryCatalog({ client });
		await catalog.listCountries();
		catalog.clear();
		await catalog.listCountries();
		expect(client.listCountries).toHaveBeenCalledTimes(2);
	});

	describe('listNumberTypeOptions', () => {
		it('reports what each in-stock type can do, asking only what the first number did not show', async () => {
			const searchNumbers = vi.fn(async (input: NumberSearchInput) => {
				if (input.numberType === 'local') {
					// UK local: texting numbers can call; pictures need their own probe and none exist.
					if (input.sms) return [number('GB', { sms: true, mms: false, voice: true })];
					return [];
				}
				// UK mobile: one texting number already shows every ability.
				if (input.sms) return [number('GB', { sms: true, mms: true, voice: true }, 'any')];
				return [];
			});
			const client = fakeClient({ searchNumbers });
			const catalog = createSmsCountryCatalog({ client });

			await expect(catalog.listNumberTypeOptions('GB')).resolves.toEqual([
				{
					numberType: 'local',
					canText: true,
					canSendPictures: false,
					canCall: true,
					addressRequirement: 'none'
				},
				{
					numberType: 'mobile',
					canText: true,
					canSendPictures: true,
					canCall: true,
					addressRequirement: 'any'
				}
			]);
			// local: sms + mms probes; mobile: sms only.
			expect(searchNumbers).toHaveBeenCalledTimes(3);
			expect(searchNumbers.mock.calls.every(([input]) => input.limit === 1)).toBe(true);
		});

		it('never marks voice-only stock as texting-ready (Brazil)', async () => {
			const searchNumbers = vi.fn(async (input: NumberSearchInput) =>
				input.voice ? [number('BR', { sms: false, mms: false, voice: true })] : []
			);
			const catalog = createSmsCountryCatalog({ client: fakeClient({ searchNumbers }) });

			await expect(catalog.listNumberTypeOptions('BR')).resolves.toEqual([
				{
					numberType: 'local',
					canText: false,
					canSendPictures: false,
					canCall: true,
					addressRequirement: null
				}
			]);
		});

		it('returns nothing for a country with no stock', async () => {
			const client = fakeClient();
			const catalog = createSmsCountryCatalog({ client });
			await expect(catalog.listNumberTypeOptions('NZ')).resolves.toEqual([]);
			expect(client.searchNumbers).not.toHaveBeenCalled();
		});
	});
});
