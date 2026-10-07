<script lang="ts">
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import OwnerSettingsForm from '$lib/components/jafar/OwnerSettingsForm.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
</script>

<OwnerSettingsForm
	title="Payment instructions"
	icon={creditCardIcon}
	fields={['payment_instructions']}
>
	{#snippet children(draft, errors)}
		<SectionBlock
			title="How to pay"
			hint="Leave out the package name and price — they are added automatically."
			form
		>
			<Textarea
				id="payment-instructions"
				label="Instructions"
				rows={8}
				required
				maxlength={5000}
				bind:value={draft.payment_instructions}
				invalid={Boolean(errors.payment_instructions)}
				errorMessage={errors.payment_instructions}
			/>
		</SectionBlock>
	{/snippet}

	{#snippet about()}
		<p>
			Shown on the “application received” page and in the receipt email, right after someone applies
			for a package.
		</p>
		<p>A receipt email already sent keeps the instructions it had.</p>
	{/snippet}
</OwnerSettingsForm>
