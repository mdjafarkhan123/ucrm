import { dev } from '$app/environment';
import { httpError } from '$lib/http-error';

// CRM launch readiness Part 12: browser alerts on this computer (docs/alerts-behavior-contract.md). Browser-only
// code: registers the alert worker, asks the browser's permission, and tells the server which computer to use.
// It is only ever reached from a person's own click, never on page load.

export type BrowserAlertSupport =
	/** This browser can receive browser alerts. */
	| 'ready'
	/** iPhone and iPad only allow it once the CRM is added to the Home Screen. */
	| 'needs-home-screen'
	| 'unsupported';

export function browserAlertSupport(): BrowserAlertSupport {
	if (typeof window === 'undefined') return 'unsupported';
	const hasEverything =
		'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
	if (hasEverything) return 'ready';
	const onApple = /iPhone|iPad|iPod/i.test(navigator.userAgent);
	const installed =
		(navigator as Navigator & { standalone?: boolean }).standalone === true ||
		window.matchMedia('(display-mode: standalone)').matches;
	return onApple && !installed ? 'needs-home-screen' : 'unsupported';
}

export type BrowserPermission = 'default' | 'granted' | 'denied';

export function browserPermission(): BrowserPermission {
	return typeof Notification === 'undefined' ? 'default' : Notification.permission;
}

/** "Chrome on Windows", the name a person recognises their own computer by. */
export function describeThisBrowser(userAgent: string): string {
	const browser = /Edg\//.test(userAgent)
		? 'Edge'
		: /OPR\/|Opera/.test(userAgent)
			? 'Opera'
			: /Firefox\//.test(userAgent)
				? 'Firefox'
				: /Chrome\/|CriOS\//.test(userAgent)
					? 'Chrome'
					: /Safari\//.test(userAgent)
						? 'Safari'
						: 'Browser';
	const system = /Android/.test(userAgent)
		? 'Android'
		: /iPhone|iPad|iPod/.test(userAgent)
			? 'iPhone'
			: /Windows/.test(userAgent)
				? 'Windows'
				: /Mac OS X|Macintosh/.test(userAgent)
					? 'Mac'
					: /CrOS/.test(userAgent)
						? 'Chromebook'
						: /Linux/.test(userAgent)
							? 'Linux'
							: 'this device';
	return `${browser} on ${system}`;
}

async function registration(): Promise<ServiceWorkerRegistration> {
	await navigator.serviceWorker.register('/service-worker.js', {
		type: dev ? 'module' : 'classic'
	});
	return navigator.serviceWorker.ready;
}

function keyBytes(base64Url: string): Uint8Array<ArrayBuffer> {
	const padded = base64Url
		.replace(/-/g, '+')
		.replace(/_/g, '/')
		.padEnd(Math.ceil(base64Url.length / 4) * 4, '=');
	const raw = atob(padded);
	const bytes = new Uint8Array(new ArrayBuffer(raw.length));
	for (let index = 0; index < raw.length; index += 1) bytes[index] = raw.charCodeAt(index);
	return bytes;
}

/** The address this browser gets alerts at, or null when it has none. Reads only; never asks permission. */
export async function thisComputerEndpoint(): Promise<string | null> {
	if (browserAlertSupport() !== 'ready') return null;
	const existing = await navigator.serviceWorker.getRegistration('/service-worker.js');
	const subscription = await existing?.pushManager.getSubscription();
	return subscription?.endpoint ?? null;
}

export type EnableResult = 'enabled' | 'blocked' | 'dismissed';

/** Asks the browser for permission (call only after our own Enable / Not now box), then registers this computer. */
export async function enableBrowserAlerts(publicKey: string): Promise<EnableResult> {
	const permission = await Notification.requestPermission();
	if (permission === 'denied') return 'blocked';
	if (permission !== 'granted') return 'dismissed';

	const worker = await registration();
	const subscription =
		(await worker.pushManager.getSubscription()) ??
		(await worker.pushManager.subscribe({
			userVisibleOnly: true,
			applicationServerKey: keyBytes(publicKey)
		}));
	const json = subscription.toJSON();
	const response = await fetch('/api/notifications/push', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({
			endpoint: subscription.endpoint,
			keys: { p256dh: json.keys?.p256dh, auth: json.keys?.auth },
			label: describeThisBrowser(navigator.userAgent)
		})
	});
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw httpError(response, result.error ?? 'Browser alerts could not be turned on.');
	}
	return 'enabled';
}

async function forgetEndpoint(endpoint: string) {
	await fetch('/api/notifications/push', {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ endpoint })
	});
}

/** Stops alerts on this computer: the server forgets it and the browser drops its subscription. */
export async function disableBrowserAlerts(): Promise<void> {
	if (browserAlertSupport() !== 'ready') return;
	const existing = await navigator.serviceWorker.getRegistration('/service-worker.js');
	const subscription = await existing?.pushManager.getSubscription();
	if (!subscription) return;
	await forgetEndpoint(subscription.endpoint);
	await subscription.unsubscribe();
}

/** Called on sign-out so the next person on a shared computer never sees this person's alerts. Never throws. */
export async function leaveThisComputer(): Promise<void> {
	try {
		await disableBrowserAlerts();
	} catch (error) {
		console.error('Could not stop browser alerts on this computer.', error);
	}
}

export async function removeComputer(id: string): Promise<void> {
	const response = await fetch('/api/notifications/push', {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ id })
	});
	if (!response.ok) throw httpError(response, 'That computer could not be removed.');
}
