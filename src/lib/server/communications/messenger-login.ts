import { env } from '$env/dynamic/private';
import type { MessengerLoginOutcome } from '$lib/communications/messenger-settings';

// Facebook's small login window lives on our own callback page once Facebook sends it back. That page hands the
// result to the Settings tab and closes. Facebook can cut the window's link to its opener, so the result also goes
// out on a same-origin BroadcastChannel, which the Settings tab listens to as well.

export const MESSENGER_LOGIN_STATE_COOKIE = 'messenger_oauth_state';
export const MESSENGER_LOGIN_COOKIE_PATH = '/api/settings/communications/messenger';
export const MESSENGER_LOGIN_CHANNEL = 'ucrm-messenger-login';

/** One fixed address, so it always matches the redirect URI saved in Meta's app dashboard. */
export function messengerAppOrigin(fallback: string): string {
	try {
		return env.APP_URL ? new URL(env.APP_URL).origin : fallback;
	} catch {
		return fallback;
	}
}

export function messengerRedirectUri(origin: string): string {
	return `${origin}${MESSENGER_LOGIN_COOKIE_PATH}/callback`;
}

export function messengerLoginWindow(outcome: MessengerLoginOutcome, origin: string): Response {
	const payload = JSON.stringify(outcome).replace(/</g, '\\u003c');
	const html = `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Facebook</title>
<style>body{font:14px system-ui,sans-serif;display:grid;place-items:center;min-height:90vh;color:#334155}</style></head>
<body><p>You can close this window.</p>
<script>
(function () {
  var outcome = ${payload};
  try { new BroadcastChannel(${JSON.stringify(MESSENGER_LOGIN_CHANNEL)}).postMessage(outcome); } catch (e) {}
  try { if (window.opener) window.opener.postMessage(outcome, ${JSON.stringify(origin)}); } catch (e) {}
  setTimeout(function () { window.close(); }, 150);
})();
</script>
</body>
</html>`;
	return new Response(html, {
		status: 200,
		headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }
	});
}
