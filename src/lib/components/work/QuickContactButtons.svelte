<script lang="ts">
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import navigationIcon from '@tabler/icons/outline/navigation.svg?raw';

	// The round buttons that reach a client from a record's header: call, text, (email) and directions to
	// the address. They open the phone's own dialer, messages app and maps, so nothing is sent from here.
	// A button with nothing behind it is not drawn, rather than drawn disabled.
	let {
		phone = null,
		email = null,
		address = null
	}: {
		phone?: string | null;
		email?: string | null;
		/** Where Directions goes: a street address, as one line. */
		address?: string | null;
	} = $props();

	const directionsHref = $derived(
		address
			? `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(address)}`
			: null
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
{#if phone}
	<a
		class="quick-contact"
		href={`tel:${phone}`}
		aria-label={`Call ${phone}`}
		title={`Call ${phone}`}
	>
		{@html phoneIcon}
	</a>
	<a
		class="quick-contact"
		href={`sms:${phone}`}
		aria-label={`Text ${phone}`}
		title={`Text ${phone}`}
	>
		{@html messageIcon}
	</a>
{/if}
{#if email}
	<a
		class="quick-contact"
		href={`mailto:${email}`}
		aria-label={`Email ${email}`}
		title={`Email ${email}`}
	>
		{@html mailIcon}
	</a>
{/if}
{#if directionsHref}
	<a
		class="quick-contact"
		href={directionsHref}
		target="_blank"
		rel="noopener"
		aria-label="Get directions"
		title="Get directions"
	>
		{@html navigationIcon}
	</a>
{/if}

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.quick-contact {
		display: inline-grid;
		width: 34px;
		height: 34px;
		place-items: center;
		border: var(--border-base) solid var(--color-border);
		border-radius: 999px;
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		text-decoration: none;
		transition: all var(--timing-base) ease-out;

		:global(svg) {
			display: block;
			width: 15px;
			height: 15px;
		}
		&:hover {
			color: var(--color-interactive);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
</style>
