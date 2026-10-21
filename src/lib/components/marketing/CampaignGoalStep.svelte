<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import {
		marketingGoals,
		marketingGoalLabels,
		marketingGoalDescriptions,
		MARKETING_CAMPAIGN_NAME_MAX,
		type MarketingGoal
	} from '$lib/marketing/campaign-content';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import rotateIcon from '@tabler/icons/outline/rotate.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';

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

	const goalIcons: Record<MarketingGoal, string> = {
		bring_back: rotateIcon,
		promote_service: tagIcon,
		announcement: speakerphoneIcon,
		blank: fileIcon
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="What is this campaign for?"
	hint="Each goal suggests who to email and how the message reads. You can change your mind later."
	icon={targetIcon}
	tone="growth"
>
	<div class="goal-body">
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
					<IconTile icon={goalIcons[option]} tone="growth" />
					<span class="goal-card__copy">
						<span class="goal-card__title">{marketingGoalLabels[option]}</span>
						<span class="goal-card__description">{marketingGoalDescriptions[option]}</span>
					</span>
					<span class="goal-card__radio" aria-hidden="true"></span>
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
			<p class="goal-body__error" role="alert">{errorMessage}</p>
		{/if}
	</div>

	{#snippet footer()}
		<span class="foot-hint">Use Save draft above to keep this for later.</span>
		<Button variant="primary" onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	{/snippet}
</SetupStepCard>

<style lang="scss">
	.goal-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
	}

	.goal-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-slim);
	}

	// A goal is one tile: its icon at the left, the title over the description, the circle at the top right.
	.goal-card {
		position: relative;
		display: flex;
		align-items: flex-start;
		gap: 14px;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
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
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&:hover {
			border-color: var(--color-border--interactive);
		}

		&:has(input:focus-visible) {
			box-shadow: var(--shadow-focus);
		}

		&--selected {
			border-color: var(--color-interactive);
			box-shadow: inset 0 0 0 0.5px var(--color-interactive);

			&:has(input:focus-visible) {
				box-shadow:
					inset 0 0 0 0.5px var(--color-interactive),
					var(--shadow-focus);
			}
		}

		&__copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
			// Keeps a long title clear of the circle.
			padding-right: var(--space-small);
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__description {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__radio {
			flex: none;
			box-sizing: border-box;
			width: 18px;
			height: 18px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			transition: border-width var(--timing-quick) ease-out;
		}

		&--selected &__radio {
			border-width: 5px;
			border-color: var(--color-interactive);
		}
	}

	.foot-hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}
</style>
