<script lang="ts">
	import bellIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import OwnerSettingsForm from '$lib/components/jafar/OwnerSettingsForm.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';

	const MAX_RECIPIENTS = 10;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<OwnerSettingsForm title="Alert recipients" icon={bellIcon} fields={['alert_recipient_emails']}>
	{#snippet children(draft, errors)}
		<SectionBlock title="Email these people" hint="Up to {MAX_RECIPIENTS} addresses." form>
			<ul class="alert-recipients">
				{#each draft.alert_recipient_emails, index (index)}
					<li class="alert-recipients__row">
						<Input
							id={`alert-recipient-${index}`}
							type="email"
							label={`Email ${index + 1}`}
							maxlength={254}
							bind:value={draft.alert_recipient_emails[index]}
						/>
						<Button
							variant="tertiary"
							disabled={draft.alert_recipient_emails.length <= 1}
							onclick={() => draft.alert_recipient_emails.splice(index, 1)}
							><span class="alert-recipients__icon" aria-hidden="true">{@html trashIcon}</span><span
								class="alert-recipients__remove-label">Remove</span
							></Button
						>
					</li>
				{/each}
			</ul>
			{#if errors.alert_recipient_emails}
				<p class="alert-recipients__error" role="alert">{errors.alert_recipient_emails}</p>
			{/if}
			<div>
				<Button
					variant="secondary"
					disabled={draft.alert_recipient_emails.length >= MAX_RECIPIENTS}
					onclick={() => draft.alert_recipient_emails.push('')}
					><span class="alert-recipients__icon" aria-hidden="true">{@html plusIcon}</span>Add email</Button
				>
			</div>
		</SectionBlock>
	{/snippet}

	{#snippet about()}
		<p>
			These addresses get an email when a new application arrives, when a payment is reversed, or
			when something fails and needs you — for example a client’s account could not be set up.
		</p>
		<p>They also get Uplift’s copy of a support reply a client has not seen yet.</p>
		<p>Everything else stays in the panel’s notifications.</p>
	{/snippet}
</OwnerSettingsForm>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.alert-recipients {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.alert-recipients__row {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.alert-recipients__icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	/* On a phone the email needs the width, so Remove shows as its icon; the word stays for screen readers. */
	@media (max-width: 639px) {
		.alert-recipients__remove-label {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}

	.alert-recipients__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
