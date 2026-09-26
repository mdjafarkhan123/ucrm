<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';

	type Channel = 'email' | 'sms';

	// Step two of "New conversation": once a client is picked, this offers only the channels that
	// client actually has a saved address or number for -- website chat is never offered here, since a
	// chat conversation needs a real visitor session, not a staff-started draft.
	let {
		open,
		clientName,
		channels,
		onCancel,
		onConfirm
	}: {
		open: boolean;
		clientName: string;
		channels: Channel[];
		onCancel: () => void;
		onConfirm: (channel: Channel) => void;
	} = $props();

	function channelLabel(value: Channel) {
		return value === 'sms' ? 'Text (SMS)' : 'Email';
	}

	let channel = $state<Channel | ''>('');
</script>

<Dialog {open} title={`Message ${clientName}`} size="small" onClose={onCancel}>
	<div class="choose-channel">
		{#if channels.length === 0}
			<p class="choose-channel__notice">
				This customer has no saved email address or phone number. Add one before starting a
				conversation.
			</p>
			<footer class="choose-channel__footer">
				<Button variant="secondary" onclick={onCancel}>Close</Button>
			</footer>
		{:else}
			<p class="choose-channel__lead">How do you want to reach {clientName}?</p>
			<Select
				id="choose-channel-channel"
				ariaLabel="Channel"
				placeholder="Choose a channel"
				options={channels.map((value) => ({ value, label: channelLabel(value) }))}
				bind:value={channel}
			/>
			<footer class="choose-channel__footer">
				<Button variant="secondary" onclick={onCancel}>Cancel</Button>
				<Button variant="primary" disabled={!channel} onclick={() => channel && onConfirm(channel)}
					>Start conversation</Button
				>
			</footer>
		{/if}
	</div>
</Dialog>

<style lang="scss">
	/* Dialog content is portaled out of this component's subtree, so its styles have to be global. */
	:global(.choose-channel) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	:global(.choose-channel__lead) {
		color: var(--color-text);
	}
	:global(.choose-channel__notice) {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface--active);
		font-size: var(--typography--fontSize-small);
	}
	:global(.choose-channel__footer) {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
