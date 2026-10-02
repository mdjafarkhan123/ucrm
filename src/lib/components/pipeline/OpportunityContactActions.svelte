<script lang="ts">
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { handOffComposerDraft } from '$lib/communications/composer-draft';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';

	type ContactMethod = { id: string; kind: 'email' | 'phone'; value: string; is_primary: boolean };

	// The three ways to reach the client from the card. Each shows only when it can work: Email and Text need a
	// saved address or number and the right to message (and the shared inbox in the plan); Call needs a number.
	//
	// Email and Text are not a second sending system. They open the client's own conversation in Communications
	// with that channel ready, and the composer there does the consent, opt-out, allowance and delivery checks.
	// It writes to the client's primary address or number, so a chooser here would only offer addresses it
	// cannot use -- the primary one is named in the button's description instead.
	//
	// Call opens the phone's dialler and nothing more. It never records that a call happened; `onCall` only
	// tells the Brief to offer the "How did it go?" bar, which a person may ignore.
	let {
		clientId,
		clientName,
		contacts,
		canMessage,
		onCall
	}: {
		clientId: string;
		clientName: string;
		contacts: ContactMethod[];
		canMessage: boolean;
		onCall: () => void;
	} = $props();

	const primaryFirst = (a: ContactMethod, b: ContactMethod) =>
		Number(b.is_primary) - Number(a.is_primary);
	const emails = $derived(contacts.filter((method) => method.kind === 'email').sort(primaryFirst));
	const phones = $derived(contacts.filter((method) => method.kind === 'phone').sort(primaryFirst));

	const conversationHref = $derived(`${resolve('/(app)/communications')}?client=${clientId}`);

	function openComposer(channel: 'email' | 'sms') {
		handOffComposerDraft({ clientId, channel, subject: '', body: '' });
	}

	function dial(number: string) {
		onCall();
		// A tel: link hands the number to the device; it is not a page of this app.
		window.location.href = `tel:${number}`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if (canMessage && (emails.length > 0 || phones.length > 0)) || phones.length > 0}
	<div class="contact-actions" role="group" aria-label={`Contact ${clientName}`}>
		{#if canMessage && emails.length > 0}
			<Button
				size="small"
				variant="secondary"
				href={conversationHref}
				onclick={() => openComposer('email')}
			>
				<span class="contact-actions__icon" aria-hidden="true">{@html mailIcon}</span>
				Email
			</Button>
		{/if}
		{#if canMessage && phones.length > 0}
			<Button
				size="small"
				variant="secondary"
				href={conversationHref}
				onclick={() => openComposer('sms')}
			>
				<span class="contact-actions__icon" aria-hidden="true">{@html messageIcon}</span>
				Text
			</Button>
		{/if}
		{#if phones.length === 1}
			<Button size="small" variant="secondary" onclick={() => dial(phones[0].value)}>
				<span class="contact-actions__icon" aria-hidden="true">{@html phoneIcon}</span>
				Call
			</Button>
		{:else if phones.length > 1}
			<!-- Several numbers on file: pick which one to dial. -->
			<DropdownMenu
				align="start"
				triggerLabel={`Call ${clientName}`}
				triggerClass="contact-actions__call"
				items={phones.map((method) => ({
					key: method.id,
					label: method.is_primary ? `${method.value} (main)` : method.value,
					icon: phoneIcon,
					onSelect: () => dial(method.value)
				}))}
			>
				{#snippet trigger()}
					<span class="contact-actions__icon" aria-hidden="true">{@html phoneIcon}</span>
					Call
				{/snippet}
			</DropdownMenu>
		{/if}
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.contact-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.contact-actions__icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	:global(.contact-actions__call) {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		min-height: 32px;
		padding: 0 var(--space-slim);
		border: var(--border-base) solid var(--color-interactive);
		border-radius: var(--radius-base);
		color: var(--color-interactive);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover,
		&:focus-visible {
			color: var(--color-interactive--hover);
			background: var(--color-surface--hover);
		}
	}
</style>
