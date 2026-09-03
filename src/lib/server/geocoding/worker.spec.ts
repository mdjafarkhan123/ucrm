import { describe, expect, it, vi } from 'vitest';
import {
	GeocodingProviderError,
	type GeocodeAddress,
	type GeocodeResult,
	type Geocoder
} from './geocoder';
import { createMockGeocoder } from './mock-geocoder';
import { drainGeocodingQueue, processClaimedProperty, type GeocodingWorkerClient } from './worker';

type PendingRow = {
	id: string;
	address_line1: string | null;
	city: string | null;
	state_region: string | null;
	postal_code: string | null;
};

type FinalizeArgs = {
	p_id: string;
	p_address_line1: string | null;
	p_city: string | null;
	p_state_region: string | null;
	p_postal_code: string | null;
	p_status: string;
	p_latitude: number | null;
	p_longitude: number | null;
};

// A fake queue: claim pops the head; finalize records the call and reports applied unless a guard is configured
// to reject it. Enough to exercise every worker branch without a database.
function fakeClient(
	pending: PendingRow[],
	options: { finalizeApplied?: (args: FinalizeArgs) => boolean } = {}
) {
	const queue = [...pending];
	const finalizeCalls: FinalizeArgs[] = [];
	const finalizeApplied = options.finalizeApplied ?? (() => true);

	const rpc = vi.fn(async (name: string, args?: Record<string, unknown>) => {
		if (name === 'claim_pending_property_for_geocoding') {
			const next = queue.shift();
			return { data: next ? [next] : [], error: null };
		}
		if (name === 'finalize_property_geocode') {
			const finalizeArgs = args as unknown as FinalizeArgs;
			finalizeCalls.push(finalizeArgs);
			return { data: finalizeApplied(finalizeArgs), error: null };
		}
		return { data: null, error: { message: `Unexpected RPC: ${name}` } };
	});

	return { client: { rpc } as GeocodingWorkerClient, rpc, finalizeCalls };
}

const throwingGeocoder = (error: unknown): Geocoder => ({
	geocode: vi.fn(async (_address: GeocodeAddress): Promise<GeocodeResult> => {
		throw error;
	})
});

const row = (over: Partial<PendingRow> = {}): PendingRow => ({
	id: 'prop-1',
	address_line1: '123 Main St',
	city: 'Austin',
	state_region: 'TX',
	postal_code: '78701',
	...over
});

describe('processClaimedProperty', () => {
	it('returns idle without geocoding when the queue is empty', async () => {
		const { client } = fakeClient([]);
		const geocode = vi.fn();

		await expect(processClaimedProperty({ client, geocoder: { geocode } })).resolves.toEqual({
			status: 'idle'
		});
		expect(geocode).not.toHaveBeenCalled();
	});

	it('geocodes a claimed property and finalizes it succeeded with coordinates', async () => {
		const { client, finalizeCalls } = fakeClient([row()]);
		const geocoder = createMockGeocoder({
			'123 main st, austin, tx, 78701': { status: 'found', latitude: 30.26, longitude: -97.74 }
		});

		await expect(processClaimedProperty({ client, geocoder })).resolves.toEqual({
			status: 'succeeded',
			propertyId: 'prop-1'
		});
		expect(finalizeCalls).toHaveLength(1);
		expect(finalizeCalls[0]).toMatchObject({
			p_id: 'prop-1',
			p_status: 'succeeded',
			p_latitude: 30.26,
			p_longitude: -97.74
		});
	});

	it('finalizes failed with no coordinates when the address does not resolve', async () => {
		const { client, finalizeCalls } = fakeClient([row()]);
		const geocoder = createMockGeocoder({
			'123 main st, austin, tx, 78701': { status: 'not_found' }
		});

		await expect(processClaimedProperty({ client, geocoder })).resolves.toEqual({
			status: 'failed',
			propertyId: 'prop-1'
		});
		expect(finalizeCalls[0]).toMatchObject({
			p_status: 'failed',
			p_latitude: null,
			p_longitude: null
		});
	});

	it('leaves the row pending (never finalizes) on a retryable provider error', async () => {
		const { client, finalizeCalls } = fakeClient([row()]);
		const geocoder = throwingGeocoder(
			new GeocodingProviderError('Rate limited', true, 'rate_limited')
		);

		await expect(processClaimedProperty({ client, geocoder })).resolves.toEqual({
			status: 'provider_error',
			propertyId: 'prop-1'
		});
		expect(finalizeCalls).toHaveLength(0);
	});

	it('leaves the row pending on a non-retryable provider error too', async () => {
		const { client, finalizeCalls } = fakeClient([row()]);
		const geocoder = throwingGeocoder(new GeocodingProviderError('Bad key', false, 'auth'));

		await expect(processClaimedProperty({ client, geocoder })).resolves.toMatchObject({
			status: 'provider_error'
		});
		expect(finalizeCalls).toHaveLength(0);
	});

	it('rethrows a non-provider error instead of swallowing a bug', async () => {
		const { client } = fakeClient([row()]);
		const geocoder = throwingGeocoder(new TypeError('undefined is not a function'));

		await expect(processClaimedProperty({ client, geocoder })).rejects.toThrow(TypeError);
	});

	it('reports skipped when finalize is rejected by its guard (address changed mid-flight)', async () => {
		const { client, finalizeCalls } = fakeClient([row()], { finalizeApplied: () => false });
		const geocoder = createMockGeocoder();

		await expect(processClaimedProperty({ client, geocoder })).resolves.toEqual({
			status: 'skipped',
			propertyId: 'prop-1'
		});
		expect(finalizeCalls).toHaveLength(1);
	});

	it('passes only the four query components to finalize as the mid-flight guard', async () => {
		const { client, finalizeCalls } = fakeClient([row({ postal_code: null, state_region: null })]);
		const geocoder = createMockGeocoder();

		await processClaimedProperty({ client, geocoder });
		expect(finalizeCalls[0]).toMatchObject({
			p_address_line1: '123 Main St',
			p_city: 'Austin',
			p_state_region: null,
			p_postal_code: null
		});
	});
});

describe('drainGeocodingQueue', () => {
	it('drains every pending property then stops idle', async () => {
		const { client } = fakeClient([row({ id: 'a' }), row({ id: 'b' }), row({ id: 'c' })]);
		const geocoder = createMockGeocoder({ 'no, where, ,': { status: 'not_found' } });

		const result = await drainGeocodingQueue({ client, geocoder });
		expect(result).toMatchObject({ claimed: 3, succeeded: 3, stoppedBy: 'idle' });
	});

	it('stops at the claim cap without draining the whole queue', async () => {
		const rows = Array.from({ length: 5 }, (_, i) => row({ id: `p-${i}` }));
		const { client } = fakeClient(rows);
		const geocoder = createMockGeocoder();

		const result = await drainGeocodingQueue({ client, geocoder, maxClaims: 2 });
		expect(result).toMatchObject({ claimed: 2, stoppedBy: 'max_claims' });
	});

	it('stops when the time budget is exhausted before the queue empties', async () => {
		const rows = Array.from({ length: 5 }, (_, i) => row({ id: `p-${i}` }));
		const { client } = fakeClient(rows);
		const geocoder = createMockGeocoder();
		// Clock jumps past the budget after the first claim is checked.
		let ticks = 0;
		const now = () => (ticks++ === 0 ? 0 : 1000);

		const result = await drainGeocodingQueue({
			client,
			geocoder,
			timeBudgetMs: 500,
			now
		});
		expect(result.stoppedBy).toBe('time_budget');
	});

	it('counts provider errors separately and keeps draining', async () => {
		const { client } = fakeClient([row({ id: 'a' }), row({ id: 'b' })]);
		let call = 0;
		const geocoder: Geocoder = {
			geocode: vi.fn(async (): Promise<GeocodeResult> => {
				call += 1;
				if (call === 1) throw new GeocodingProviderError('down', true, 'network');
				return { status: 'found', latitude: 1, longitude: 2 };
			})
		};

		const result = await drainGeocodingQueue({ client, geocoder });
		expect(result).toMatchObject({ claimed: 2, providerError: 1, succeeded: 1, stoppedBy: 'idle' });
	});
});
