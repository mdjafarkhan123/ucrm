/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />

// CRM launch readiness Part 12: shows a browser alert when the server sends one, and opens the right record when
// it is clicked. It caches nothing and never touches page requests.

const worker = self as unknown as ServiceWorkerGlobalScope;

type AlertPayload = { title?: string; body?: string; url?: string; tag?: string };

worker.addEventListener('install', () => {
	void worker.skipWaiting();
});

worker.addEventListener('activate', (event) => {
	event.waitUntil(worker.clients.claim());
});

worker.addEventListener('push', (event) => {
	let payload: AlertPayload = {};
	try {
		payload = (event.data?.json() ?? {}) as AlertPayload;
	} catch {
		payload = { title: event.data?.text() };
	}

	event.waitUntil(
		(async () => {
			// Someone looking at the CRM right now already sees the bell; a second pop-up is noise.
			const windows = await worker.clients.matchAll({ type: 'window', includeUncontrolled: true });
			if (windows.some((client) => client.focused)) return;
			await worker.registration.showNotification(payload.title || 'New alert', {
				body: payload.body,
				tag: payload.tag,
				data: { url: payload.url ?? '/' }
			});
		})()
	);
});

worker.addEventListener('notificationclick', (event) => {
	event.notification.close();
	const target = new URL(
		(event.notification.data as { url?: string } | undefined)?.url ?? '/',
		worker.location.origin
	).href;

	event.waitUntil(
		(async () => {
			const windows = await worker.clients.matchAll({ type: 'window', includeUncontrolled: true });
			const open = windows.find((client) => 'focus' in client);
			if (open) {
				await open.focus();
				if ('navigate' in open) await (open as WindowClient).navigate(target);
				return;
			}
			await worker.clients.openWindow(target);
		})()
	);
});
