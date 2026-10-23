<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import type { TextingTask } from '$lib/jafar/texting-setup';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';

	// Can't turn on (board `v6Jtu`): why, for the log, and the words the business sees in place of Setting up.
	let {
		task,
		saving,
		error,
		onClose,
		onSubmit
	}: {
		task: TextingTask;
		saving: boolean;
		error: string;
		onClose: () => void;
		onSubmit: (input: { reason: string; business_message: string }) => void;
	} = $props();

	const MESSAGE_LIMIT = 400;
	const reasons = [
		'Twilio won’t allow this country for this account',
		'This country needs paperwork the business doesn’t have',
		'Texting this country is too risky right now',
		'The business asked to cancel'
	].map((label) => ({ value: label, label }));

	const country = $derived(countryDisplayName(task.country));
	let reason = $state('');
	let reasonMissing = $state(false);
	// The pop-up opens fresh for each task, so the suggested words start from its country.
	let message = $state(
		untrack(
			() =>
				`We can’t switch on texting to ${countryDisplayName(task.country)} for your account right now. Your other countries keep working. Reply here if you have questions.`
		)
	);

	function submit() {
		reasonMissing = !reason;
		if (reasonMissing || !message.trim()) return;
		onSubmit({ reason, business_message: message.trim() });
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	open
	width={600}
	title={`Can’t turn on ${country}`}
	subtitle={`${task.organization_name}’s request closes and they are told why.`}
	icon={banIcon}
	iconTone="critical"
	closeDisabled={saving}
	initialFocusId="cant-turn-on-reason"
	{onClose}
>
	<div class="cant-turn-on">
		{#if error}<FormErrorSummary message={error} hint="Nothing was changed." />{/if}
		<Select
			id="cant-turn-on-reason"
			label="Reason"
			required
			options={reasons}
			placeholder="Choose a reason"
			bind:value={reason}
			invalid={reasonMissing}
			errorMessage={reasonMissing ? 'Choose a reason.' : ''}
			disabled={saving}
		/>
		<Textarea
			id="cant-turn-on-message"
			label={`What ${task.organization_name} sees`}
			rows={4}
			maxlength={MESSAGE_LIMIT}
			bind:value={message}
			invalid={!message.trim()}
			errorMessage={message.trim() ? '' : 'Write what the business sees.'}
			disabled={saving}
		/>
	</div>
	{#snippet footer()}
		<Button variant="secondary" onclick={onClose} disabled={saving}>Cancel</Button>
		<Button variation="destructive" onclick={submit} loading={saving}>
			{#if !saving}<span aria-hidden="true">{@html banIcon}</span>{/if}
			{saving ? 'Closing…' : 'Close request'}
		</Button>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.cant-turn-on {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
</style>
