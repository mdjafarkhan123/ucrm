import { page } from '$app/state';
import { replaceState } from '$app/navigation';

/**
 * One query parameter a page keeps in the address bar -- an open tab, usually -- so a refresh or a shared
 * link lands on the same view.
 *
 * SvelteKit's `replaceState` rewrites the address without updating `page.url`, so `page.url` cannot be the
 * source of truth: a page deriving its tab from it stays on the old tab after a click while the tab strip
 * shows the new one, and any fetch gated on that tab silently never runs. The value lives here instead,
 * derived from the address the page opened at, re-derived when a real navigation arrives with another, and
 * written back with `replaceState` (not a navigation), so Back still leaves the page rather than stepping
 * through tabs. `fallback` is the default view, which carries no parameter.
 *
 * Call during component setup. Checking the value against the page's own list of tabs stays with the page.
 */
export function urlParam(name: string, fallback: string) {
	// Writable derived: a click overrides it locally, and a real navigation re-derives it from the address.
	let value = $derived(page.url.searchParams.get(name));

	return {
		get current() {
			return value ?? fallback;
		},
		set(next: string) {
			value = next === fallback ? null : next;
			// The live address, not `page.url`: after any earlier replaceState on this page `page.url` is stale,
			// and building from it would quietly undo that earlier change. A throwaway value, never reactive state.
			// eslint-disable-next-line svelte/prefer-svelte-reactivity
			const url = new URL(location.href);
			if (next === fallback) url.searchParams.delete(name);
			else url.searchParams.set(name, next);
			// This is the current page's own address with one parameter changed, not a route id.
			// eslint-disable-next-line svelte/no-navigation-without-resolve
			replaceState(url, page.state);
		}
	};
}
