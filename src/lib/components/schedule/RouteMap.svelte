<script lang="ts">
	import 'mapbox-gl/dist/mapbox-gl.css';
	import { onMount } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { PUBLIC_MAPBOX_TOKEN } from '$env/static/public';
	import type { RouteStop } from '$lib/schedule/route-order';
	import { stopAddressLabel, stopClientLabel, stopPropertyId } from '$lib/schedule/stops';
	import { geocodeAddress, type GeoPoint } from '$lib/schedule/geocode-client';
	import type { Map as MapboxMap, Marker } from 'mapbox-gl';

	// The live map half of the contextual route workspace (Schedule 7b, path A2). It draws the selected
	// employee's stops as numbered pins in route order and a line through them, using Mapbox GL. Stops that
	// already carry stored coordinates are pinned straight away; the rest are geocoded in the browser for this
	// session only (see geocode-client) so pins appear before server-side stored geocoding exists. A stop that
	// has no address, or does not resolve, simply gets no pin -- it stays in the list beside the map.

	let {
		stops,
		selectedItemId = null,
		onselect
	}: {
		/** The employee's stops, already in the route order the list shows. Position numbers follow this order. */
		stops: RouteStop[];
		selectedItemId?: string | null;
		/** Same contract as the list: the clicked stop plus a DOM element to anchor its preview popover to. */
		onselect: (stop: RouteStop, element: HTMLElement) => void;
	} = $props();

	const hasToken = PUBLIC_MAPBOX_TOKEN.length > 0;

	// The stops that still need a browser lookup: an address to resolve but no coordinates stored yet. Deduped
	// by property, since two stops at one address share a single lookup. A stop with stored coordinates or no
	// address is never in here.
	const pendingLookups = $derived.by(() => {
		const seen = new Set<string>();
		const lookups: { key: string; address: string }[] = [];
		for (const stop of stops) {
			if (stop.property_latitude !== null && stop.property_longitude !== null) continue;
			const address = stopAddressLabel(stop);
			if (!address) continue;
			const key = stopPropertyId(stop) ?? stop.id;
			if (seen.has(key)) continue;
			seen.add(key);
			lookups.push({ key, address });
		}
		return lookups;
	});

	// One query resolves every pending address for display. It runs only while the map is mounted (it mounts
	// with the open workspace), caches per session, and never goes stale -- an address does not move. The
	// result is a map of lookup key -> point; a key missing from it means that address did not resolve.
	const geocodeQuery = createQuery(() => ({
		queryKey: ['schedule', 'geocode', pendingLookups.map((l) => `${l.key}:${l.address}`).sort()],
		queryFn: async ({ signal }) => {
			const entries = await Promise.all(
				pendingLookups.map(
					async (l) =>
						[l.key, await geocodeAddress(l.address, PUBLIC_MAPBOX_TOKEN, signal)] as const
				)
			);
			return Object.fromEntries(entries) as Record<string, GeoPoint | null>;
		},
		enabled: hasToken && pendingLookups.length > 0,
		staleTime: Infinity,
		gcTime: 60 * 60 * 1000
	}));

	const geocoded = $derived(geocodeQuery.data ?? {});

	// Every stop that can be placed, in route order, with its position number and coordinates -- stored ones
	// first, a display lookup otherwise. Stops that cannot be placed fall out here and live only in the list.
	type PlacedStop = { stop: RouteStop; position: number; point: GeoPoint };
	const placed = $derived.by(() => {
		const out: PlacedStop[] = [];
		stops.forEach((stop, index) => {
			const position = index + 1;
			if (stop.property_latitude !== null && stop.property_longitude !== null) {
				out.push({
					stop,
					position,
					point: { lng: stop.property_longitude, lat: stop.property_latitude }
				});
				return;
			}
			const key = stopPropertyId(stop) ?? stop.id;
			const point = geocoded[key];
			if (point) out.push({ stop, position, point });
		});
		return out;
	});

	const placedCount = $derived(placed.length);
	const unplacedCount = $derived(stops.length - placedCount);
	const locating = $derived(geocodeQuery.isFetching && placedCount === 0);

	// --- Mapbox lifecycle -----------------------------------------------------------------------------------
	// A third-party imperative library, so it lives in an effect: created on mount, torn down on destroy, and
	// re-synced whenever the placed stops or the selection change. Markers are DOM overlays we own in
	// `markers`; the route line is a GeoJSON source/layer we (re)add on every style load.

	let container: HTMLDivElement | undefined = $state();
	let map: MapboxMap | null = null;
	let mapboxgl: typeof import('mapbox-gl').default | null = null;
	let ready = $state(false);
	const markers = new Map<string, { marker: Marker; el: HTMLButtonElement }>();

	const STYLES = {
		light: 'mapbox://styles/mapbox/streets-v12',
		dark: 'mapbox://styles/mapbox/dark-v11'
	} as const;

	function currentTheme(): 'light' | 'dark' {
		const attr = document.documentElement.getAttribute('data-theme');
		if (attr === 'dark') return 'dark';
		if (attr === 'light') return 'light';
		return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
	}

	onMount(() => {
		if (!hasToken) return;
		let disposed = false;
		let stopThemeWatch: (() => void) | null = null;

		(async () => {
			mapboxgl = (await import('mapbox-gl')).default;
			if (disposed || !container) return;
			mapboxgl.accessToken = PUBLIC_MAPBOX_TOKEN;
			map = new mapboxgl.Map({
				container,
				style: STYLES[currentTheme()],
				center: [-98, 39], // a neutral continental view until the first stops set the bounds
				zoom: 3,
				attributionControl: true
			});
			map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), 'top-right');
			map.on('load', () => {
				ready = true;
				drawRoute();
			});
			// A theme swap re-styles the map; markers are DOM overlays and survive, but the route source/layer is
			// wiped, so re-add it once the new style has loaded.
			map.on('style.load', drawRoute);
			stopThemeWatch = watchTheme(() => map?.setStyle(STYLES[currentTheme()]));
		})();

		return () => {
			disposed = true;
			stopThemeWatch?.();
			for (const { marker } of markers.values()) marker.remove();
			markers.clear();
			map?.remove();
			map = null;
			ready = false;
		};
	});

	// Watch both the explicit in-app theme choice (data-theme on <html>) and the OS preference, and call back
	// when either changes. Returns a disposer.
	function watchTheme(onChange: () => void): () => void {
		const observer = new MutationObserver(onChange);
		observer.observe(document.documentElement, {
			attributes: true,
			attributeFilter: ['data-theme']
		});
		const media = window.matchMedia('(prefers-color-scheme: dark)');
		media.addEventListener('change', onChange);
		return () => {
			observer.disconnect();
			media.removeEventListener('change', onChange);
		};
	}

	// Rebuild the pins whenever the placed stops change. Cheap at route scale (one employee, one day), and it
	// keeps the marker set exactly in step with the list without hand-diffing.
	$effect(() => {
		if (!ready || !map || !mapboxgl) return;
		syncMarkers();
		fitToStops();
	});

	// Selection is applied on its own so clicking a pin only re-highlights -- it never rebuilds markers or
	// re-fits the map, which would yank the view on every click. It also re-runs after a rebuild (it reads
	// `placed`) so a freshly created marker gets its highlight without waiting for the next selection change.
	$effect(() => {
		void placed;
		for (const [id, { el }] of markers) {
			el.classList.toggle('route-map__pin--selected', id === selectedItemId);
		}
	});

	function syncMarkers() {
		if (!map || !mapboxgl) return;
		const wanted = new Set(placed.map((p) => p.stop.id));
		for (const [id, { marker }] of markers) {
			if (!wanted.has(id)) {
				marker.remove();
				markers.delete(id);
			}
		}
		for (const p of placed) {
			const existing = markers.get(p.stop.id);
			if (existing) {
				existing.marker.setLngLat([p.point.lng, p.point.lat]);
				existing.el.textContent = String(p.position);
				continue;
			}
			const el = document.createElement('button');
			el.type = 'button';
			el.className = 'route-map__pin';
			el.textContent = String(p.position);
			el.setAttribute(
				'aria-label',
				`Stop ${p.position}: ${stopClientLabel(p.stop)}${
					stopAddressLabel(p.stop) ? `, ${stopAddressLabel(p.stop)}` : ''
				}`
			);
			el.addEventListener('click', (event) => {
				event.stopPropagation();
				onselect(p.stop, el);
			});
			const marker = new mapboxgl.Marker({ element: el, anchor: 'bottom' })
				.setLngLat([p.point.lng, p.point.lat])
				.addTo(map);
			markers.set(p.stop.id, { marker, el });
		}
		drawRoute();
	}

	// The route line: a single GeoJSON source, added under the pins, updated in place when it already exists so
	// a re-style or a marker change never leaves a duplicate layer behind.
	function drawRoute() {
		if (!map || !ready) return;
		const line = {
			type: 'Feature' as const,
			properties: {},
			geometry: {
				type: 'LineString' as const,
				coordinates: placed.map((p) => [p.point.lng, p.point.lat])
			}
		};
		const source = map.getSource('route') as import('mapbox-gl').GeoJSONSource | undefined;
		if (source) {
			source.setData(line);
			return;
		}
		map.addSource('route', { type: 'geojson', data: line });
		map.addLayer({
			id: 'route-line',
			type: 'line',
			source: 'route',
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: {
				'line-color': '#2f8f5b',
				'line-width': 3,
				'line-opacity': 0.85
			}
		});
	}

	function fitToStops() {
		if (!map || !mapboxgl || placed.length === 0) return;
		if (placed.length === 1) {
			map.easeTo({ center: [placed[0].point.lng, placed[0].point.lat], zoom: 13, duration: 400 });
			return;
		}
		const bounds = new mapboxgl.LngLatBounds();
		for (const p of placed) bounds.extend([p.point.lng, p.point.lat]);
		map.fitBounds(bounds, { padding: 64, maxZoom: 15, duration: 400 });
	}
</script>

<div class="route-map">
	{#if !hasToken}
		<div class="route-map__notice">
			<p class="route-map__notice-title">Map not configured</p>
			<p class="route-map__notice-text">A Mapbox token is needed to show the map.</p>
		</div>
	{:else}
		<div class="route-map__canvas" bind:this={container}></div>

		{#if locating}
			<div class="route-map__badge" role="status">Locating stops…</div>
		{:else if placedCount === 0}
			<div class="route-map__notice route-map__notice--overlay">
				<p class="route-map__notice-title">No stops to place yet</p>
				<p class="route-map__notice-text">
					{stops.length === 0
						? 'There are no stops on this day.'
						: 'None of these addresses could be located. Each stop still offers Directions in the list.'}
				</p>
			</div>
		{:else if unplacedCount > 0}
			<div class="route-map__badge" role="status">
				{placedCount} of {stops.length} placed · {unplacedCount} in the list only
			</div>
		{/if}
	{/if}
</div>

<style lang="scss">
	.route-map {
		position: relative;
		flex: 1 1 auto;
		min-width: 0;
		height: 100%;
	}

	.route-map__canvas {
		position: absolute;
		inset: 0;
	}

	.route-map__badge {
		position: absolute;
		top: var(--space-small);
		left: var(--space-small);
		z-index: 2;
		padding: var(--space-smaller) var(--space-small);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		box-shadow: var(--shadow-low);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.route-map__notice {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		align-items: center;
		justify-content: center;
		text-align: center;
		padding: var(--space-large);
		height: 100%;
	}

	.route-map__notice--overlay {
		position: absolute;
		inset: 0;
		z-index: 2;
		background-color: color-mix(in srgb, var(--color-surface) 80%, transparent);
		pointer-events: none;
	}

	.route-map__notice-title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.route-map__notice-text {
		margin: 0;
		max-width: 320px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	/* The pin is created imperatively and placed by Mapbox outside this component's DOM, so its styles are
	   global. Kept namespaced to `route-map__pin` so nothing else picks them up. A circular numbered marker,
	   the way route apps number their stops -- the number stays upright and legible. */
	:global(.route-map__pin) {
		display: grid;
		place-items: center;
		width: 26px;
		height: 26px;
		padding: 0;
		border: 2px solid #fff;
		border-radius: 50%;
		background-color: #2f8f5b;
		color: #fff;
		font-size: 12px;
		font-weight: 700;
		line-height: 1;
		box-shadow: 0 1px 4px #0000004d;
		cursor: pointer;
		transition:
			transform var(--timing-quick) ease,
			background-color var(--timing-quick) ease;
	}

	:global(.route-map__pin:hover) {
		background-color: #276f48;
		transform: scale(1.1);
	}

	:global(.route-map__pin:focus-visible) {
		outline: none;
		box-shadow: 0 0 0 3px color-mix(in srgb, #2f8f5b 45%, transparent);
	}

	:global(.route-map__pin--selected) {
		background-color: #1f6fd6;
		transform: scale(1.2);
		z-index: 3;
	}

	:global(.route-map__pin--selected:hover) {
		background-color: #1a5fbb;
		transform: scale(1.25);
	}
</style>
