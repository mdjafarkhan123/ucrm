<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		marketingGoals,
		marketingGoalLabels,
		marketingGoalDescriptions,
		MARKETING_CAMPAIGN_NAME_MAX,
		type MarketingGoal
	} from '$lib/marketing/campaign-content';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 1 (blueprint §8 step 1): pick why this campaign exists and give it a name only staff sees.
	// Nothing here writes to the server -- Save draft (owned by the journey shell) is the only save action.
	let {
		name = $bindable(),
		goal = $bindable(),
		errorMessage = '',
		onContinue
	}: {
		name: string;
		goal: MarketingGoal | null;
		errorMessage?: string;
		onContinue: () => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="panel">
	<header class="panel__head">
		<h2>What is this campaign for?</h2>
		<p>
			Each goal suggests who to email and how the message reads. You can change your mind later.
		</p>
	</header>

	<div class="panel__body">
		<div class="goal-grid" role="radiogroup" aria-label="Campaign goal">
			{#each marketingGoals as option (option)}
				<label class="goal-card" class:goal-card--selected={goal === option}>
					<input
						type="radio"
						name="campaign-goal"
						value={option}
						checked={goal === option}
						onchange={() => (goal = option)}
					/>
					<span class="goal-card__title">{marketingGoalLabels[option]}</span>
					<span class="goal-card__description">{marketingGoalDescriptions[option]}</span>
				</label>
			{/each}
		</div>

		<Input
			id="campaign-name"
			label="Campaign name (only your team sees this)"
			bind:value={name}
			required
			maxlength={MARKETING_CAMPAIGN_NAME_MAX}
			placeholder="e.g. Spring tune-up reminder"
		/>

		{#if errorMessage}
			<p class="panel__error" role="alert">{errorMessage}</p>
		{/if}
	</div>

	<footer class="panel__foot">
		<span class="foot-hint">Use Save draft above to keep this for later.</span>
		<Button variant="primary" onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	</footer>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
		}

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	.goal-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: var(--space-base);
	}

	.goal-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		cursor: pointer;
		transition:
			border-color var(--timing-quick) ease-out,
			box-shadow var(--timing-quick) ease-out;

		input {
			position: absolute;
			width: 1px;
			height: 1px;
			opacity: 0;
		}

		&:hover {
			border-color: var(--color-border--interactive);
		}

		&:has(input:focus-visible) {
			box-shadow: var(--shadow-focus);
		}

		&--selected {
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 1px var(--color-interactive);
		}

		&__title {
			font-weight: 600;
			color: var(--color-heading);
		}

		&__description {
			font-size: var(--typography--fontSize-small);
			color: var(--color-text--secondary);
		}
	}

	.foot-hint {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
