<script lang="ts">
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import PreviewScreenshots from './PreviewScreenshots.svelte';
	import type { PreviewCard, PreviewScreenshotUrls } from '$lib/setup/preview';

	// Client onboarding E3: what Uplift wrote on one preview card — its summary, its link and its screenshots —
	// as both the client and Jafar read it.
	let { card, urls }: { card: PreviewCard; urls: PreviewScreenshotUrls } = $props();
</script>

<div class="preview-card-body">
	<p class="preview-card-body__summary">{card.summary}</p>
	{#if card.link}
		<a class="preview-card-body__link" href={card.link} target="_blank" rel="noopener noreferrer">
			Open the preview
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span class="preview-card-body__icon" aria-hidden="true">{@html externalLinkIcon}</span>
			<span class="preview-card-body__hidden">(opens in a new tab)</span>
		</a>
	{/if}
	{#if card.screenshots.length > 0}
		<PreviewScreenshots value={card.screenshots} {urls} />
	{/if}
</div>

<style lang="scss">
	.preview-card-body {
		display: grid;
		gap: var(--space-small);

		&__summary {
			margin: 0;
			color: var(--color-text);
			white-space: pre-line;
		}

		&__link {
			display: inline-flex;
			align-items: center;
			justify-self: start;
			gap: var(--space-smallest);
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				color: var(--color-interactive--hover);
				text-decoration: underline;
			}

			&:focus-visible {
				outline: 2px solid var(--color-interactive);
				outline-offset: 2px;
			}
		}

		&__icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}
</style>
