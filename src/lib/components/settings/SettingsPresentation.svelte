<script lang="ts">
	import type { Snippet } from 'svelte';
	import SettingsPageHeader from './SettingsPageHeader.svelte';
	let {
		title,
		description,
		icon,
		iconTone = 'job',
		children
	}: {
		title: string;
		description: string;
		icon: string;
		iconTone?: 'job' | 'invoice' | 'quote' | 'task';
		children: Snippet;
	} = $props();
</script>

<div
	class="business-settings"
	style={`--settings-icon-color: var(--color-${iconTone}); --settings-icon-surface: var(--color-${iconTone}--surface)`}
>
	<SettingsPageHeader {title} {description} {icon} tone={iconTone} presentation="business" />
	{@render children()}
</div>

<style lang="scss">
	.business-settings {
		:global(.record-form__main) {
			padding: 0;
			border: 0;
			background: transparent;
			box-shadow: none;
			overflow: visible;
		}
		:global(.record-form__header) {
			display: none;
		}
		:global(.section-block) {
			margin: 0;
			padding: 24px;
			background: var(--color-surface);
			gap: 16px;
		}
		:global(.section-block .section-block__title) {
			position: static;
			max-width: none;
			transform: none;
			padding: 0;
			background: transparent;
			font-size: 16px;
		}
		:global(.section-block legend.section-block__title) {
			float: left;
			width: 100%;
			margin-bottom: 16px;
		}
		:global(.section-block__hint) {
			margin: -8px 0 0;
		}
		:global(.section-block__icon) {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			background: var(--settings-icon-surface);
		}
		:global(.section-block__icon svg) {
			color: var(--settings-icon-color);
		}
		:global(.sticky-action-bar) {
			max-width: 720px;
			margin-inline: auto;
			background: var(--color-base-blue--900);
			color: var(--color-base-white);
			justify-content: flex-end;
		}
	}
</style>
