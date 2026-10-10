<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { replaceState } from '$app/navigation';
	import { onMount } from 'svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { jafarBookingGoogleKey } from '$lib/jafar/query-keys';
	import { fetchGoogleStatus, type GoogleStatus } from '$lib/jafar/booking';

	// Jafar business management E5: connect Jafar's Google so a Google Meet meeting type in automatic mode makes one Meet call
	// per booking, on Jafar's own Google Calendar. Connecting goes to Google's own sign-in and returns here with the result in the address.

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: jafarBookingGoogleKey,
		queryFn: fetchGoogleStatus
	}));
	const status = $derived(query.data);

	let confirmDisconnect = $state(false);
	let disconnecting = $state(false);

	const RETURNS: Record<string, { ok: boolean; words: string }> = {
		connected: {
			ok: true,
			words: 'Google is connected. New Google Meet bookings get their own Meet link.'
		},
		declined: {
			ok: false,
			words: 'Google was not connected: the sign-in was not finished or lacked calendar access.'
		},
		expired: {
			ok: false,
			words: 'That sign-in took too long or came from another browser. Try again.'
		},
		failed: { ok: false, words: 'Google could not be connected. Please try again.' },
		not_set_up: { ok: false, words: 'Google is not set up on this server yet.' }
	};

	onMount(() => {
		const result = RETURNS[page.url.searchParams.get('google') ?? ''];
		if (!result) return;
		if (result.ok) toast.success(result.words);
		else toast.error(result.words);
		void queryClient.invalidateQueries({ queryKey: jafarBookingGoogleKey });
		const clean = new URL(page.url);
		clean.searchParams.delete('google');
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		replaceState(clean, {});
	});

	async function disconnect() {
		disconnecting = true;
		const result = await sendLeadWrite('/api/jafar/booking/google', 'DELETE', {});
		disconnecting = false;
		confirmDisconnect = false;
		if (!result.ok) {
			toast.error(result.error);
			return;
		}
		queryClient.setQueryData(jafarBookingGoogleKey, result.data as GoogleStatus);
		toast.success('Google is disconnected. Calendar events already made stay in Google Calendar.');
	}
</script>

{#if query.isError && !status}
	<p class="google-connection__note">Google's status could not be loaded. {query.error.message}</p>
{:else if !status}
	<p class="google-connection__note">Checking Google…</p>
{:else}
	<div class="google-connection">
		<div>
			<p class="google-connection__title">
				{#if status.connected && !status.needs_reconnect}
					<Badge status="success">Connected</Badge>
				{:else if status.needs_reconnect}
					<Badge status="warning">Needs reconnecting</Badge>
				{:else}
					<Badge status="inactive">Not connected</Badge>
				{/if}
				{#if status.email}<span class="google-connection__who">{status.email}</span>{/if}
			</p>
			<p class="google-connection__note">
				{#if status.needs_reconnect}
					Google stopped accepting the saved sign-in, so new bookings are told the link will follow.
					Connect again to make Meet links automatically.
				{:else if status.connected}
					Each booking of a Google Meet meeting type in automatic mode gets its own Calendar event
					and Meet link, which moves or is deleted with the booking.
				{:else if !status.configured}
					Google is not set up on this server yet, so it cannot be connected.
				{:else}
					Connect your Google account so each booking gets its own Meet link and the visitor is
					emailed it. Without it, you add the link on each call.
				{/if}
			</p>
		</div>
		<div class="google-connection__actions" data-sveltekit-reload>
			{#if status.connected}
				<Button variant="secondary" onclick={() => (confirmDisconnect = true)}>Disconnect</Button>
			{/if}
			{#if !status.connected || status.needs_reconnect}
				<Button href="/api/jafar/booking/google/connect" disabled={!status.configured}
					>Connect Google</Button
				>
			{/if}
		</div>
	</div>

	<ConfirmDialog
		open={confirmDisconnect}
		title="Disconnect Google?"
		confirmLabel="Disconnect"
		destructive
		loading={disconnecting}
		onConfirm={() => void disconnect()}
		onClose={() => (confirmDisconnect = false)}
	>
		<p>
			New Google Meet bookings will tell the visitor the link will follow, and you add it on each
			call. Events already made stay as they are.
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.google-connection {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.google-connection__title {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin: 0 0 var(--space-small);
	}

	.google-connection__who {
		font-weight: 600;
		color: var(--color-heading);
		overflow-wrap: anywhere;
	}

	.google-connection__note {
		margin: 0;
		max-width: 40rem;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.google-connection__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
</style>
