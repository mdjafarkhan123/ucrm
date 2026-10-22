<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';

	// Display-only progress track for the campaign journey (design skill `layout.md` → Setup steps → New
	// campaign): each step stacks its tile over the label and hint, joined by lines level with the tiles. Same
	// contract as ImportStepper: it never navigates. The draft lives in local state across all five steps and
	// only Save draft or Back/Continue changes it, so a click on the track itself does nothing.
	let { current }: { current: number } = $props();

	const steps = [
		{ n: 1, title: 'Goal', hint: 'Why this campaign', icon: targetIcon },
		{ n: 2, title: 'Customers', hint: 'Who receives it', icon: usersIcon },
		{ n: 3, title: 'Email', hint: 'Build the message', icon: mailIcon },
		{ n: 4, title: 'Delivery', hint: 'Button and replies', icon: sendIcon },
		{ n: 5, title: 'Review', hint: 'Check and launch', icon: listCheckIcon }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ol class="campaign-stepper" aria-label="Campaign steps">
	{#each steps as step, index (step.n)}
		{@const state = step.n < current ? 'done' : step.n === current ? 'active' : 'upcoming'}
		{#if index > 0}
			<li
				class={['campaign-stepper__line', step.n <= current && 'campaign-stepper__line--done']}
				aria-hidden="true"
			></li>
		{/if}
		<li
			class="campaign-stepper__step campaign-stepper__step--{state}"
			aria-current={state === 'active' ? 'step' : undefined}
		>
			<span class="campaign-stepper__tile" aria-hidden="true">
				{@html state === 'done' ? checkIcon : step.icon}
			</span>
			<span class="campaign-stepper__label">
				<b>{step.title}</b>
				<span>{step.hint}</span>
			</span>
		</li>
	{/each}
</ol>

<style lang="scss">
	.campaign-stepper {
		display: flex;
		align-items: flex-start;
		margin: 0;
		padding: var(--space-base) var(--space-medium);
		list-style: none;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__step {
			display: flex;
			flex: 0 0 112px;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
			text-align: center;
		}

		// Level with the middle of the 32 tiles, so it reads as one line through the steps.
		&__line {
			flex: 1 1 24px;
			min-width: 12px;
			height: 2px;
			margin-top: 15px;
			border-radius: var(--radius-circle);
			background: var(--color-border);

			&--done {
				background: var(--color-success);
			}
		}

		&__tile {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			.campaign-stepper__step--done & {
				border-color: var(--color-success--surface-edge);
				background: var(--color-success--surface);
				color: var(--color-success);
			}
			.campaign-stepper__step--active & {
				border-color: transparent;
				background: var(--color-interactive);
				color: var(--color-text--reverse);
			}
		}

		// The hint can be a little wider than its 112 slot; it overhangs the line gap evenly on both sides.
		&__label {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: 1px;
			line-height: var(--typography--lineHeight-tight);
			white-space: nowrap;

			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			.campaign-stepper__step--active & b {
				font-weight: 700;
			}
			.campaign-stepper__step--upcoming & b {
				color: var(--color-text--secondary);
			}
		}
	}
</style>
