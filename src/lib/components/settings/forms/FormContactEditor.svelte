<script lang="ts">
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import type { ContactBlock } from '$lib/forms/types';

	// Edits the locked contact section of a request form. Name is always collected; the rest can be shown,
	// made required, and (for email/phone) carry a marketing opt-in — matching Jobber's contact block
	// (jobber-02 § 4.4). A hidden field cannot be required, so its "Required" box disables when it is hidden;
	// the "reach the customer somehow" rule is enforced on save by the API.
	let { contact }: { contact: ContactBlock } = $props();

	const contactable = [
		{ key: 'email' as const, label: 'Email address' },
		{ key: 'phone' as const, label: 'Phone number' }
	];
	const plain = [
		{ key: 'company' as const, label: 'Company' },
		{ key: 'address' as const, label: 'Address' }
	];

	// Keep the data honest as toggles change: hiding a field clears its Required and consent flags so a save
	// never carries a contradiction the API would reject.
	function onShownChange(key: 'email' | 'phone' | 'company' | 'address', shown: boolean) {
		contact[key].shown = shown;
		if (!shown) {
			contact[key].required = false;
			if (key === 'email' || key === 'phone') contact[key].marketing_consent = false;
		}
	}
</script>

<div class="contact-editor">
	<div class="contact-editor__row">
		<div class="contact-editor__field">
			<span class="contact-editor__name">Name</span>
			<span class="contact-editor__always">Always collected</span>
		</div>
		<Checkbox id="contact-name-required" label="Required" bind:checked={contact.name.required} />
	</div>

	{#each contactable as field (field.key)}
		<div class="contact-editor__row">
			<Checkbox
				id={`contact-${field.key}-shown`}
				label={field.label}
				checked={contact[field.key].shown}
				onchange={(next) => onShownChange(field.key, next)}
			/>
			<div class="contact-editor__opts">
				<Checkbox
					id={`contact-${field.key}-required`}
					label="Required"
					bind:checked={contact[field.key].required}
					disabled={!contact[field.key].shown}
				/>
				<Checkbox
					id={`contact-${field.key}-consent`}
					label="Ask for marketing opt-in"
					bind:checked={contact[field.key].marketing_consent}
					disabled={!contact[field.key].shown}
				/>
			</div>
		</div>
	{/each}

	{#each plain as field (field.key)}
		<div class="contact-editor__row">
			<Checkbox
				id={`contact-${field.key}-shown`}
				label={field.label}
				checked={contact[field.key].shown}
				onchange={(next) => onShownChange(field.key, next)}
			/>
			<Checkbox
				id={`contact-${field.key}-required`}
				label="Required"
				bind:checked={contact[field.key].required}
				disabled={!contact[field.key].shown}
			/>
		</div>
	{/each}
</div>

<style lang="scss">
	.contact-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__row {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__field {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__name {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__always {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__opts {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-slim) var(--space-base);
			padding-left: var(--space-large);
		}
	}
</style>
