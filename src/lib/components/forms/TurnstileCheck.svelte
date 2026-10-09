<script lang="ts">
	import { onMount } from 'svelte';

	// Cloudflare Turnstile, the "are you human" check on public forms. The script loads only when this mounts, so
	// a page pays for it only once the visitor reaches the step that submits. Without a site key (local
	// development) it draws nothing and the server skips the check. A spent or expired token is rejected like none
	// at all, so the token empties whenever the widget expires or errors; call reset() after a failed submit.

	type TurnstileApi = {
		render: (
			container: HTMLElement,
			options: {
				sitekey: string;
				callback: (token: string) => void;
				'expired-callback': () => void;
				'error-callback': () => void;
			}
		) => string | undefined;
		reset: (widgetId?: string) => void;
	};

	let { siteKey, token = $bindable('') }: { siteKey: string; token?: string } = $props();

	let container = $state<HTMLDivElement>();
	let widgetId: string | undefined;
	let api: TurnstileApi | undefined;

	const SCRIPT_SRC = 'https://challenges.cloudflare.com/turnstile/v0/api.js';

	function draw() {
		api = (window as unknown as { turnstile?: TurnstileApi }).turnstile;
		if (!api || !container || widgetId !== undefined) return;
		widgetId = api.render(container, {
			sitekey: siteKey,
			callback: (value) => (token = value),
			'expired-callback': () => (token = ''),
			'error-callback': () => (token = '')
		});
	}

	onMount(() => {
		if (!siteKey) return;
		if ((window as unknown as { turnstile?: TurnstileApi }).turnstile) {
			draw();
			return;
		}
		let script = document.querySelector<HTMLScriptElement>(`script[src="${SCRIPT_SRC}"]`);
		if (!script) {
			script = document.createElement('script');
			script.src = SCRIPT_SRC;
			script.async = true;
			script.defer = true;
			document.head.appendChild(script);
		}
		script.addEventListener('load', draw, { once: true });
		return () => script?.removeEventListener('load', draw);
	});

	export function reset() {
		token = '';
		if (api && widgetId !== undefined) api.reset(widgetId);
	}
</script>

{#if siteKey}
	<div class="turnstile-check" bind:this={container}></div>
{/if}

<style lang="scss">
	.turnstile-check {
		min-height: 65px;
	}
</style>
