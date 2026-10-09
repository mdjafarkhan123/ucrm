<script lang="ts">
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import {
		customerNoticeStatusKey,
		fetchCustomerNoticeStatus,
		type CustomerNoticeKind
	} from '$lib/schedule/customer-notices';

	// Client reminders Part 4: the "Notify customer" box on a scheduling screen, ticked by default as Housecall Pro
	// does. It appears only while the email it would send is switched on in Automations, so it never promises a
	// message that does not go out. `kinds` names which emails this save could send: a first booking, a move, or
	// either when one save can be both.
	let {
		id,
		checked = $bindable(true),
		kinds,
		disabled = false,
		visible = $bindable(false)
	}: {
		id: string;
		checked?: boolean;
		kinds: CustomerNoticeKind[];
		disabled?: boolean;
		/** Whether the box is on screen. A screen sends "notify" only when it is visible and ticked, so a
		 *  hidden box can never email anyone. */
		visible?: boolean;
	} = $props();

	const statusQuery = createQuery(() => ({
		queryKey: customerNoticeStatusKey,
		queryFn: fetchCustomerNoticeStatus,
		staleTime: 30_000
	}));

	const active = $derived(kinds.filter((kind) => statusQuery.data?.[kind] === true));
	$effect(() => {
		visible = active.length > 0;
	});
	const description = $derived(
		active.length > 1
			? 'Email them a booking confirmation, or the new time if this visit moved.'
			: active[0] === 'booked'
				? 'Email them a booking confirmation.'
				: 'Email them the new date and time.'
	);
</script>

{#if active.length > 0}
	<div class="notify-customer">
		<Checkbox {id} bind:checked label="Notify customer" {description} {disabled} />
	</div>
{/if}

<style lang="scss">
	.notify-customer {
		padding-top: var(--space-small);
	}
</style>
