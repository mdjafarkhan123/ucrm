<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import type { NextStep } from './add-number';

	// "WHAT HAPPENS NEXT": three boxes joined by chevrons (`concept.pen` board `qaFQf`), shared by the bill and the
	// bought view.
	let { steps }: { steps: NextStep[] } = $props();
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="next-steps" aria-labelledby="add-number-next">
	<h4 id="add-number-next" class="next-steps__title">What happens next</h4>
	<ol class="next-steps__list">
		{#each steps as step, index (step.title)}
			{#if index > 0}
				<li class="next-steps__arrow" aria-hidden="true">{@html chevronRightIcon}</li>
			{/if}
			<li class="next-steps__box">
				<IconTile icon={step.icon} tone={step.tone} size={24} />
				<strong>{step.title}</strong>
				<span>{step.hint}</span>
			</li>
		{/each}
	</ol>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.next-steps {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__title {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__list {
			display: flex;
			align-items: stretch;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__box {
			display: flex;
			flex: 1 1 0;
			flex-direction: column;
			gap: var(--space-smaller);
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);

			strong {
				margin-top: var(--space-smaller);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				line-height: var(--typography--lineHeight-large);
			}
		}

		&__arrow {
			display: flex;
			align-items: center;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}
</style>
