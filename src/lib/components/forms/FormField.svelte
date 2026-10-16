<script lang="ts">
	import type { Snippet } from 'svelte';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';

	let {
		label,
		forId,
		hint,
		error,
		required = false,
		children
	}: {
		label: string;
		forId: string;
		hint?: string;
		error?: string;
		required?: boolean;
		children: Snippet;
	} = $props();
</script>

<div class="form-field">
	<label class="form-field__label" for={forId}
		>{label}{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
	>
	{@render children()}
	{#if hint && !error}<p class="form-field__hint" id={`${forId}-hint`}>{hint}</p>{/if}
	{#if error}<p class="form-field__error" id={`${forId}-error`} role="alert">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{error}
		</p>{/if}
</div>

<style lang="scss">
	.form-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.form-field__label {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
	}
	.form-field__hint,
	.form-field__error {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.form-field__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-critical);
	}
	.form-field__error span :global(svg) {
		width: 16px;
		height: 16px;
	}
</style>
