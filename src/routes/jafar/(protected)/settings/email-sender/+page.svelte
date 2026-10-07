<script lang="ts">
	import mailForwardIcon from '@tabler/icons/outline/mail-forward.svg?raw';
	import OwnerSettingsForm from '$lib/components/jafar/OwnerSettingsForm.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
</script>

<OwnerSettingsForm
	title="Sender name & reply-to"
	icon={mailForwardIcon}
	fields={['sender_display_name', 'reply_to_address']}
>
	{#snippet children(draft, errors)}
		<SectionBlock title="Outgoing email" form>
			<Input
				id="sender-display-name"
				label="Sender name"
				required
				maxlength={200}
				bind:value={draft.sender_display_name}
				invalid={Boolean(errors.sender_display_name)}
				errorMessage={errors.sender_display_name}
			/>
			<Input
				id="reply-to-address"
				type="email"
				label="Reply-to address"
				required
				maxlength={254}
				autocomplete="email"
				bind:value={draft.reply_to_address}
				invalid={Boolean(errors.reply_to_address)}
				errorMessage={errors.reply_to_address}
			/>
		</SectionBlock>
	{/snippet}

	{#snippet about()}
		<p>
			The sender name is meant to be the “From” name on Uplift’s emails, and the reply-to address
			where people’s replies arrive.
		</p>
		<p>
			Not in use yet: Uplift’s emails still come from the system address with no name, and replies
			go back to that address. What you save here is kept ready for when emails start using it.
		</p>
	{/snippet}
</OwnerSettingsForm>
