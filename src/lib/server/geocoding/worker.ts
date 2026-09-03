// Schedule Part 7a-4: the background geocoding worker.
//
// Jobber-style async geocoding: saving a property returns instantly with the row 'pending' (7a-3), and this
// worker fills in the coordinates out of band. One wake drains the pending queue in bounded, sequential steps —
// claim the oldest pending property, ask the INJECTED geocoder where its address is, and write the result back.
// The geocoder is the mock today and managed Mapbox in 7b; this module only knows the `Geocoder` interface, so
// nothing here changes when the real provider plugs in.
//
// Sequential, not concurrent: the real provider is rate-limited, so one-at-a-time is the safe default and the
// smallest shape that works. Overlapping wakes are allowed — the claim's `for update skip locked` (in
// claim_pending_property_for_geocoding) is the exactly-once boundary, exactly like the automation worker. There
// is no lease and no stale-claim quarantine: the row stays 'pending' through the whole cycle, so a wake that
// dies mid-flight loses nothing — the next wake simply re-claims and retries.

import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	GeocodingProviderError,
	type GeocodeAddress,
	type Geocoder
} from '$lib/server/geocoding/geocoder';

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type GeocodingWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

// The four address components the claim returns — the same fields the geocoder query is built from and that
// finalize guards on to detect an address edited mid-flight.
type ClaimedProperty = {
	id: string;
	address_line1: string | null;
	city: string | null;
	state_region: string | null;
	postal_code: string | null;
};

// One claim/geocode/finalize attempt. 'idle' means the queue held no claimable row. 'provider_error' means the
// geocoder could not answer (network/rate-limit/auth) — the row is deliberately left 'pending' to retry, never
// finalized. 'skipped' means finalize's guard rejected the write (the row was finalized or its address changed
// under us) — no error, just nothing recorded this attempt.
export type ProcessedGeocodeResult =
	| { status: 'idle' }
	| { status: 'succeeded' | 'failed' | 'provider_error' | 'skipped'; propertyId: string };

export type GeocodingDrainResult = {
	claimed: number;
	succeeded: number;
	failed: number;
	providerError: number;
	skipped: number;
	stoppedBy: 'idle' | 'max_claims' | 'time_budget';
};

type WorkerDependencies = {
	client?: GeocodingWorkerClient;
	geocoder: Geocoder;
};

type DrainOptions = {
	maxClaims?: number;
	timeBudgetMs?: number;
	now?: () => number;
};

// Conservative defaults, to verify rather than to claim capacity. A single wake never geocodes more than
// DEFAULT_MAX_CLAIMS properties or runs past the time budget, both well under the route's HTTP timeout.
const DEFAULT_MAX_CLAIMS = 50;
const DEFAULT_TIME_BUDGET_MS = 20_000;

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: GeocodingWorkerClient): GeocodingWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as GeocodingWorkerClient);
}

function toGeocodeAddress(property: ClaimedProperty): GeocodeAddress {
	return {
		line1: property.address_line1,
		city: property.city,
		state_region: property.state_region,
		postal_code: property.postal_code
	};
}

// One claim/geocode/finalize cycle. Claims the oldest pending property; if the queue is empty, reports idle.
// Otherwise geocodes it and writes the outcome back through finalize_property_geocode, which is guarded so a
// stale result (address changed mid-flight, or already finalized) is dropped rather than winning.
export async function processClaimedProperty(
	dependencies: WorkerDependencies
): Promise<ProcessedGeocodeResult> {
	const client = resolveClient(dependencies.client);
	const geocoder = dependencies.geocoder;

	const claimed = await client.rpc('claim_pending_property_for_geocoding');
	if (claimed.error) throw rpcError('Could not claim a property for geocoding', claimed.error);
	const property = Array.isArray(claimed.data)
		? (claimed.data[0] as ClaimedProperty | undefined)
		: undefined;
	if (!property) return { status: 'idle' };

	let status: 'succeeded' | 'failed';
	let latitude: number | null = null;
	let longitude: number | null = null;

	try {
		const result = await geocoder.geocode(toGeocodeAddress(property));
		if (result.status === 'found') {
			status = 'succeeded';
			latitude = result.latitude;
			longitude = result.longitude;
		} else {
			// The provider ran and the address does not resolve. This is a durable fact, not a failure: record
			// it so the stop keeps its place in the route list with an explanation.
			status = 'failed';
		}
	} catch (error) {
		// The provider could not answer at all. Leave the row pending so a real address is never marked
		// unresolvable because Mapbox was briefly unreachable; the next wake retries it. A non-provider error
		// (a bug) still surfaces to the caller.
		if (error instanceof GeocodingProviderError) {
			return { status: 'provider_error', propertyId: property.id };
		}
		throw error;
	}

	const finalized = await client.rpc('finalize_property_geocode', {
		p_id: property.id,
		p_address_line1: property.address_line1,
		p_city: property.city,
		p_state_region: property.state_region,
		p_postal_code: property.postal_code,
		p_status: status,
		p_latitude: latitude,
		p_longitude: longitude
	});
	if (finalized.error) throw rpcError('Could not finalize a property geocode', finalized.error);

	// finalize returns false when its guard rejected the write (already finalized, or the address changed under
	// us and this result is for the old address). Report that distinctly so it is not counted as a real outcome.
	if (finalized.data === false) return { status: 'skipped', propertyId: property.id };

	return { status, propertyId: property.id };
}

// One wake: drain the pending queue sequentially until it is idle, the claim cap is reached, or the time budget
// expires. Each cycle is its own claim, so a hot backlog is bounded per wake and the next wake continues.
export async function drainGeocodingQueue(
	dependencies: WorkerDependencies & DrainOptions
): Promise<GeocodingDrainResult> {
	const client = resolveClient(dependencies.client);
	const geocoder = dependencies.geocoder;
	const maxClaims = Math.max(1, Math.floor(dependencies.maxClaims ?? DEFAULT_MAX_CLAIMS));
	const timeBudgetMs = Math.max(0, dependencies.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const now = dependencies.now ?? Date.now;
	const deadline = now() + timeBudgetMs;

	const result: GeocodingDrainResult = {
		claimed: 0,
		succeeded: 0,
		failed: 0,
		providerError: 0,
		skipped: 0,
		stoppedBy: 'idle'
	};

	while (true) {
		if (result.claimed >= maxClaims) {
			result.stoppedBy = 'max_claims';
			return result;
		}
		if (now() >= deadline) {
			result.stoppedBy = 'time_budget';
			return result;
		}

		const processed = await processClaimedProperty({ client, geocoder });
		if (processed.status === 'idle') {
			result.stoppedBy = 'idle';
			return result;
		}

		result.claimed += 1;
		if (processed.status === 'succeeded') result.succeeded += 1;
		else if (processed.status === 'failed') result.failed += 1;
		else if (processed.status === 'provider_error') result.providerError += 1;
		else result.skipped += 1;
	}
}
