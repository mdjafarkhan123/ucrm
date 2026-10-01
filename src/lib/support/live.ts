import { supabase } from '$lib/supabase.client';

// Live delivery for the Uplift Support Messenger, both sides (plan §7). The database sends a small ids-only
// ping on a private Realtime channel whenever a message arrives or a read mark moves; the caller then
// refreshes its queries, which re-read through the permission-checked API. A ping never carries a message.
// This is the same Broadcast-from-database shape the customer inbox uses for Website Chat.
//
// While the live connection is down, the caller is asked to refresh every 30 seconds (only while the tab is
// on screen), and once more the moment the connection comes back, so nothing missed in between is lost.

const COALESCE_MS = 300;
export const SUPPORT_FALLBACK_REFRESH_MS = 30_000;

export function listenForSupportActivity(topic: string, refresh: () => void): () => void {
	let pending: ReturnType<typeof setTimeout> | null = null;
	let fallback: ReturnType<typeof setInterval> | null = null;
	let connectedBefore = false;

	// A burst of pings — a few messages in a row, or a read mark right after a reply — is one refresh.
	function schedule() {
		if (pending !== null) return;
		pending = setTimeout(() => {
			pending = null;
			refresh();
		}, COALESCE_MS);
	}

	function startFallback() {
		if (fallback !== null) return;
		fallback = setInterval(() => {
			if (document.visibilityState === 'visible') refresh();
		}, SUPPORT_FALLBACK_REFRESH_MS);
	}

	function stopFallback() {
		if (fallback === null) return;
		clearInterval(fallback);
		fallback = null;
	}

	const channel = supabase.channel(topic, { config: { private: true } });
	channel.on('broadcast', { event: 'support_activity' }, schedule);
	channel.on('broadcast', { event: 'support_read' }, schedule);
	channel.subscribe((status) => {
		if (status === 'SUBSCRIBED') {
			stopFallback();
			// The first join follows the page's own first load; a later one is a reconnect, so catch up.
			if (connectedBefore) schedule();
			connectedBefore = true;
		} else {
			// CHANNEL_ERROR, TIMED_OUT or CLOSED. The client keeps trying to rejoin on its own.
			startFallback();
		}
	});

	return () => {
		if (pending !== null) clearTimeout(pending);
		stopFallback();
		void supabase.removeChannel(channel);
	};
}
