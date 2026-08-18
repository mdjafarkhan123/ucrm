<script lang="ts">
	import type { Snippet } from 'svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import idCardIcon from '@tabler/icons/outline/id.svg?raw';

	// The first block on any create page — new request, new quote, new job, new invoice. All four ask the
	// same three things in the same place: what to call this piece of work, who it is for, and the
	// handful of facts that belong to this kind of record.
	//
	// Only the last part changes between them, so it comes in as a snippet: a request shows the date it
	// was requested, a quote shows its number, an invoice adds issue date and payment terms.
	let {
		title = $bindable(''),
		id = 'primary-info',
		heading = 'Primary Info',
		icon = idCardIcon,
		titleLabel = 'Title',
		titleRequired = false,
		titleInvalid = false,
		titleError = '',
		client,
		fields,
		class: className = ''
	}: {
		title?: string;
		/** Prefix for the ids inside the block, so two of these can never collide. */
		id?: string;
		heading?: string;
		/** Tabler icon for this kind of record, imported with `?raw`. */
		icon?: string;
		titleLabel?: string;
		titleRequired?: boolean;
		titleInvalid?: boolean;
		titleError?: string;
		/** The client picker. Left column, under the title. */
		client?: Snippet;
		/** This record's own fields or facts. Right column, beside the picker. */
		fields?: Snippet;
		class?: string;
	} = $props();
</script>

<SectionBlock
	{id}
	title={heading}
	{icon}
	variant="filled"
	level={2}
	form
	class={`primary-info ${className}`}
>
	<Input
		id={`${id}-title`}
		label={titleLabel}
		bind:value={title}
		required={titleRequired}
		invalid={titleInvalid}
		errorMessage={titleError}
	/>

	{#if client || fields}
		<div class="primary-info__row">
			<div class="primary-info__client">
				{#if client}{@render client()}{/if}
			</div>
			<div class="primary-info__fields">
				{#if fields}{@render fields()}{/if}
			</div>
		</div>
	{/if}
</SectionBlock>

<style lang="scss">
	.primary-info__row {
		display: grid;
		align-items: start;
		gap: var(--space-large);
		grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
	}

	.primary-info__client,
	.primary-info__fields {
		min-width: 0;
	}

	@media (max-width: 767px) {
		.primary-info__row {
			gap: var(--space-base);
			grid-template-columns: 1fr;
		}
	}
</style>
