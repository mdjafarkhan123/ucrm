<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import type { WarmupCard } from '$lib/marketing/warmup';
	import flameIcon from '@tabler/icons/outline/flame.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import rosetteIcon from '@tabler/icons/outline/rosette-discount-check.svg?raw';

	// How far the Marketing sending domain has warmed up (M6f). Everything shown here comes worded from
	// describeMarketingWarmup; this only lays it out: where on the ladder, how much of today is used, and what
	// earns the next step.
	let { card }: { card: WarmupCard } = $props();

	const steps = $derived(Array.from({ length: card.totalSteps }, (_, index) => index + 1));
	const usedPercent = $derived(card.today ? Math.round(card.today.fraction * 100) : 0);
</script>

<SectionBlock
	title="Sending warm-up"
	icon={flameIcon}
	hint={card.graduated
		? undefined
		: 'Inbox providers trust a new sending domain slowly. Your daily limit grows as your emails land well.'}
>
	<div class="warmup">
		<div class="warmup__summary">
			<div class="warmup__headline-group">
				{#if card.graduated}
					<span class="warmup__graduated-icon" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html rosetteIcon}
					</span>
				{/if}
				<div>
					<p class="warmup__eyebrow">{card.graduated ? 'Warm-up' : 'Today’s limit'}</p>
					<p class="warmup__headline">{card.headline}</p>
				</div>
			</div>
			<p class="warmup__step-label">{card.stepLabel}</p>
		</div>

		<ol class="warmup__ladder" aria-label={card.stepLabel}>
			{#each steps as step (step)}
				{@const state =
					card.graduated || step < card.step ? 'done' : step === card.step ? 'current' : 'next'}
				<li
					class="warmup__rung warmup__rung--{state}"
					aria-current={state === 'current' ? 'step' : undefined}
				>
					<span class="warmup__rung-bar" aria-hidden="true"></span>
					<span class="warmup__rung-label">
						<span class="warmup__visually-hidden">
							{state === 'done' ? 'Completed:' : state === 'current' ? 'Current:' : 'Upcoming:'}
						</span>
						Step {step}
					</span>
				</li>
			{/each}
		</ol>

		{#if card.today}
			<div class="warmup__today">
				<div class="warmup__today-row">
					<span class="warmup__today-label">Used today</span>
					<span class="warmup__today-value">{card.today.label}</span>
				</div>
				<span
					class="warmup__meter"
					class:warmup__meter--full={card.today.fraction >= 1}
					role="progressbar"
					aria-label="Marketing emails sent today"
					aria-valuemin="0"
					aria-valuemax={card.today.limit}
					aria-valuenow={card.today.sent}
					aria-valuetext={card.today.label}
				>
					<span class="warmup__meter-fill" style:width="{usedPercent}%"></span>
				</span>
			</div>
		{/if}

		{#if card.unlockTitle}
			<div class="warmup__unlock">
				<p class="warmup__unlock-title">{card.unlockTitle}</p>
				<ul class="warmup__requirements">
					{#each card.requirements as requirement (requirement.key)}
						<li
							class="warmup__requirement"
							class:warmup__requirement--met={requirement.met}
							class:warmup__requirement--problem={requirement.key === 'quality' && !requirement.met}
						>
							<span class="warmup__check" aria-hidden="true">
								{#if requirement.met}
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html checkIcon}
								{/if}
							</span>
							<span>
								<span class="warmup__visually-hidden">{requirement.met ? 'Done:' : 'To do:'}</span>
								{requirement.label}
							</span>
						</li>
					{/each}
				</ul>
			</div>
		{/if}

		{#if card.note}
			<p class="warmup__note">{card.note}</p>
		{/if}
	</div>
</SectionBlock>

<style lang="scss">
	.warmup {
		display: grid;
		gap: var(--space-large);
	}

	.warmup__summary {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
		flex-wrap: wrap;
	}

	.warmup__headline-group {
		display: flex;
		align-items: center;
		gap: var(--space-base);
	}

	.warmup__graduated-icon {
		display: inline-grid;
		place-items: center;
		width: 4rem;
		height: 4rem;
		border-radius: var(--radius-circle);
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);

		:global(svg) {
			width: 2.4rem;
			height: 2.4rem;
		}
	}

	.warmup__eyebrow {
		margin: 0 0 var(--space-smallest);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.warmup__headline {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
		color: var(--color-heading);
	}

	.warmup__step-label {
		margin: 0;
		padding: var(--space-smaller) var(--space-small);
		border-radius: var(--radius-large);
		background: var(--color-surface--background);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		color: var(--color-heading);
	}

	.warmup__ladder {
		display: grid;
		grid-auto-flow: column;
		grid-auto-columns: 1fr;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.warmup__rung {
		display: grid;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.warmup__rung-bar {
		height: 0.8rem;
		border-radius: var(--radius-large);
		background: var(--color-surface--background);
		border: var(--border-base) solid var(--color-border);
	}

	.warmup__rung-label {
		font-size: var(--typography--fontSize-smaller);
		color: var(--color-text--secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.warmup__rung--done .warmup__rung-bar {
		background: var(--color-success);
		border-color: var(--color-success);
	}

	.warmup__rung--current {
		.warmup__rung-bar {
			background: var(--color-interactive);
			border-color: var(--color-interactive);
		}

		.warmup__rung-label {
			font-weight: 600;
			color: var(--color-heading);
		}
	}

	.warmup__today {
		display: grid;
		gap: var(--space-small);
	}

	.warmup__today-row {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		flex-wrap: wrap;
		font-size: var(--typography--fontSize-small);
	}

	.warmup__today-label {
		color: var(--color-text--secondary);
	}

	.warmup__today-value {
		font-weight: 600;
		color: var(--color-heading);
		font-variant-numeric: tabular-nums;
	}

	.warmup__meter {
		display: block;
		height: 0.8rem;
		overflow: hidden;
		border-radius: var(--radius-large);
		background: var(--color-surface--background);
	}

	.warmup__meter-fill {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--color-interactive);
		transition: width 300ms ease;

		@media (prefers-reduced-motion: reduce) {
			transition: none;
		}
	}

	.warmup__meter--full .warmup__meter-fill {
		background: var(--color-warning);
	}

	.warmup__unlock {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}

	.warmup__unlock-title {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.warmup__requirements {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.warmup__requirement {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		color: var(--color-text);
	}

	.warmup__check {
		display: inline-grid;
		place-items: center;
		flex: 0 0 auto;
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-circle);
		border: var(--border-thick) solid var(--color-border);

		:global(svg) {
			width: 1.2rem;
			height: 1.2rem;
		}
	}

	.warmup__requirement--met {
		color: var(--color-text--secondary);

		.warmup__check {
			border-color: var(--color-success);
			background: var(--color-success);
			color: var(--color-text--reverse);
		}
	}

	.warmup__requirement--problem {
		color: var(--color-critical);

		.warmup__check {
			border-color: var(--color-critical);
		}
	}

	.warmup__note {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.warmup__visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
</style>
