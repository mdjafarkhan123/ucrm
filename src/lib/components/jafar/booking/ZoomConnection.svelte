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
	import { jafarBookingZoomKey } from '$lib/jafar/query-keys';
	import { fetchZoomStatus, type ZoomStatus } from '$lib/jafar/booking';

	// Jafar business management E4b: connect Jafar's Zoom so a Zoom meeting type in automatic mode makes one meeting
	// per booking. Connecting goes to Zoom's own sign-in and returns here with the result in the address.

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({ queryKey: jafarBookingZoomKey, queryFn: fetchZoomStatus }));
	const status = $derived(query.data);

	let confirmDisconnect = $state(false);
	let disconnecting = $state(false);

	const RETURNS: Record<string, { ok: boolean; words: string }> = {
		connected: { ok: true, words: 'Zoom is connected. New Zoom bookings get their own meeting.' },
		declined: { ok: false, words: 'Zoom was not connected: the sign-in was not finished.' },
		expired: {
			ok: false,
			words: 'That sign-in took too long or came from another browser. Try again.'
		},
		failed: { ok: false, words: 'Zoom could not be connected. Please try again.' },
		not_set_up: { ok: false, words: 'Zoom is not set up on this server yet.' }
	};

	onMount(() => {
		const result = RETURNS[page.url.searchParams.get('zoom') ?? ''];
		if (!result) return;
		if (result.ok) toast.success(result.words);
		else toast.error(result.words);
		void queryClient.invalidateQueries({ queryKey: jafarBookingZoomKey });
		const clean = new URL(page.url);
		clean.searchParams.delete('zoom');
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		replaceState(clean, {});
	});

	async function disconnect() {
		disconnecting = true;
		const result = await sendLeadWrite('/api/jafar/booking/zoom', 'DELETE', {});
		disconnecting = false;
		confirmDisconnect = false;
		if (!result.ok) {
			toast.error(result.error);
			return;
		}
		queryClient.setQueryData(jafarBookingZoomKey, result.data as ZoomStatus);
		toast.success('Zoom is disconnected. Meetings already made stay in Zoom.');
	}
</script>

{#if query.isError && !status}
	<p class="zoom-connection__note">Zoom's status could not be loaded. {query.error.message}</p>
{:else if !status}
	<p class="zoom-connection__note">Checking Zoom…</p>
{:else}
	<div class="zoom-connection">
		<div>
			<p class="zoom-connection__title">
				{#if status.connected && !status.needs_reconnect}
					<Badge status="success">Connected</Badge>
				{:else if status.needs_reconnect}
					<Badge status="warning">Needs reconnecting</Badge>
				{:else}
					<Badge status="inactive">Not connected</Badge>
				{/if}
				{#if status.email}<span class="zoom-connection__who">{status.email}</span>{/if}
			</p>
			<p class="zoom-connection__note">
				{#if status.needs_reconnect}
					Zoom stopped accepting the saved sign-in, so new bookings are told the link will follow.
					Connect again to make meetings automatically.
				{:else if status.connected}
					Each booking of a Zoom meeting type in automatic mode gets its own meeting, which moves or
					is deleted with the booking.
				{:else if !status.configured}
					Zoom is not set up on this server yet, so it cannot be connected.
				{:else}
					Connect your Zoom so each booking gets its own meeting and the visitor is emailed the
					joining link. Without it, you add the link on each call.
				{/if}
			</p>
		</div>
		<div class="zoom-connection__actions" data-sveltekit-reload>
			{#if status.connected}
				<Button variant="secondary" onclick={() => (confirmDisconnect = true)}>Disconnect</Button>
			{/if}
			{#if !status.connected || status.needs_reconnect}
				<Button href="/api/jafar/booking/zoom/connect" disabled={!status.configured}
					>Connect Zoom</Button
				>
			{/if}
		</div>
	</div>

	<ConfirmDialog
		open={confirmDisconnect}
		title="Disconnect Zoom?"
		confirmLabel="Disconnect"
		destructive
		loading={disconnecting}
		onConfirm={() => void disconnect()}
		onClose={() => (confirmDisconnect = false)}
	>
		<p>
			New Zoom bookings will tell the visitor the link will follow, and you add it on each call.
			Meetings already made stay as they are.
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.zoom-connection {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.zoom-connection__title {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin: 0 0 var(--space-small);
	}

	.zoom-connection__who {
		font-weight: 600;
		color: var(--color-heading);
		overflow-wrap: anywhere;
	}

	.zoom-connection__note {
		margin: 0;
		max-width: 40rem;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.zoom-connection__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
</style>
