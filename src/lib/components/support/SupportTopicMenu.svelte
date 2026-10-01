<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { SUPPORT_TOPICS, supportTopicLabel, type SupportTopic } from '$lib/support/api';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// A chat's topic (D4a), shown as a small pill. Whoever may change it — the chat's starter, an owner or
	// admin, or Uplift — opens a menu from the pill; everyone else sees the pill alone. The change itself
	// writes a grey line in the chat, so this component never shows its own confirmation.
	let {
		topic,
		canChange = false,
		onChange
	}: {
		topic: SupportTopic;
		canChange?: boolean;
		/** Resolves once saved; a rejection leaves the topic as it was. */
		onChange?: (topic: SupportTopic) => Promise<void>;
	} = $props();

	let saving = $state(false);

	async function choose(next: SupportTopic) {
		if (next === topic || !onChange) return;
		saving = true;
		try {
			await onChange(next);
		} finally {
			saving = false;
		}
	}

	const items = $derived(
		SUPPORT_TOPICS.map((item) => ({
			label: item.label,
			key: item.value,
			trailingIcon: item.value === topic ? checkIcon : undefined,
			note: item.value === topic ? 'current topic' : undefined,
			onSelect: () => void choose(item.value)
		}))
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if canChange && onChange}
	<DropdownMenu
		{items}
		align="start"
		triggerClass="support-topic-menu__trigger"
		triggerLabel={`Topic: ${supportTopicLabel(topic)}. Change topic`}
		disabled={saving}
	>
		{#snippet trigger()}
			<span>{supportTopicLabel(topic)}</span>
			<span class="support-topic-menu__chevron" aria-hidden="true">{@html chevronIcon}</span>
		{/snippet}
	</DropdownMenu>
{:else}
	<span class="support-topic-menu__pill">{supportTopicLabel(topic)}</span>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.support-topic-menu__pill,
	:global(.support-topic-menu__trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		min-height: 22px;
		padding: 0 var(--space-small);
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font: inherit;
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 1;
		white-space: nowrap;
	}

	:global(.support-topic-menu__trigger) {
		cursor: pointer;

		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			cursor: progress;
			opacity: 0.7;
		}
	}

	.support-topic-menu__chevron {
		display: inline-flex;

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}
</style>
