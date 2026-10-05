<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import {
		buildStartDate,
		PROJECT_STATE_LABEL,
		type ProjectStep,
		type ProjectView
	} from '$lib/setup/project-state';

	// Client onboarding E1 (plan §5): where the client's project stands, like a parcel tracker — the current step
	// in words with its dates, a bar of every step, and the full list with the day each one happened.
	let { project }: { project: ProjectView } = $props();

	const step = (state: ProjectStep['state']) => project.steps.find((each) => each.state === state);
	const readyDay = $derived(step('ready_for_uplift')?.on ?? null);
	const range = $derived(step('ready_for_review')?.range ?? null);

	/** A `YYYY-MM-DD` day reads the same wherever it is opened; a moment reads in the viewer's own day. */
	function day(value: string, withYear = false) {
		const dateOnly = value.length === 10;
		return new Date(dateOnly ? `${value}T12:00:00Z` : value).toLocaleDateString(undefined, {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
			...(withYear ? { year: 'numeric' } : {}),
			...(dateOnly ? { timeZone: 'UTC' } : {})
		});
	}

	function detail(each: ProjectStep): string | null {
		switch (each.state) {
			case 'payment_verifying':
				return each.on ? `Confirmed ${day(each.on)}` : null;
			case 'complete_setup':
			case 'uplift_reviewing':
				return each.on ? `Sent ${day(each.on)}` : null;
			case 'ready_for_uplift':
				return each.on ? `Accepted ${day(each.on)}` : null;
			case 'building':
				if (!each.on) return null;
				return each.status === 'upcoming' ? `Starts ${day(each.on)}` : `Started ${day(each.on)}`;
			case 'ready_for_review':
				if (each.status !== 'upcoming' && each.on) return `Preview sent ${day(each.on)}`;
				return each.range
					? `Expected ${day(each.range.from)} – ${day(each.range.to, true)}`
					: '7–10 business days after Uplift accepts your setup';
			default:
				return null;
		}
	}

	const reviewRange = $derived(
		range ? `between ${day(range.from)} and ${day(range.to, true)}` : null
	);
</script>

<SectionBlock title="Your project" hint="Step {project.position} of {project.total}">
	<div class="project-tracker">
		<div class="project-tracker__now" aria-live="polite">
			<span class="project-tracker__eyebrow">Now</span>
			<strong class="project-tracker__state">{PROJECT_STATE_LABEL[project.state]}</strong>
			<p>
				{#if project.state === 'complete_setup'}
					Answer your setup tasks and send them to Uplift. Your 7–10 business-day build starts once
					Uplift accepts them.
				{:else if project.state === 'uplift_reviewing'}
					Uplift is checking what you sent. It will accept it or ask you to change something.
				{:else if project.state === 'waiting_for_information'}
					Uplift needs a change before your build can start. Change what Uplift asked for and send
					your setup again.
				{:else if project.state === 'ready_for_uplift' && readyDay && reviewRange}
					Uplift has everything it needs. Building starts on {day(buildStartDate(readyDay))}, and
					your system will be ready for you to review {reviewRange}.
				{:else if project.state === 'building' && readyDay && reviewRange}
					Uplift started on {day(buildStartDate(readyDay))}. Your system will be ready for you to
					review {reviewRange} — 7–10 business days, Monday to Friday.
				{:else if project.state === 'ready_for_review'}
					Uplift has built your system. Look through each part of the preview below and tell Uplift
					what looks right and what needs a change.
				{/if}
			</p>
			{#if project.after_ready?.kind === 'returned'}
				<p class="project-tracker__note">
					Uplift sent back {project.after_ready.count === 1
						? 'one task'
						: `${project.after_ready.count} tasks`} from the changes you sent. Your build carries on while
					you change {project.after_ready.count === 1 ? 'it' : 'them'}.
				</p>
			{:else if project.after_ready?.kind === 'changes_sent'}
				<p class="project-tracker__note">Uplift is looking at the changes you sent.</p>
			{:else if project.after_ready?.kind === 'notes_sent'}
				<p class="project-tracker__note">
					You sent your notes on {day(project.after_ready.at)}. Uplift is working on them and will
					send you an updated preview.
				</p>
			{/if}
		</div>

		<div class="project-tracker__bar" aria-hidden="true">
			{#each project.steps as each (each.state)}
				<span class="project-tracker__segment project-tracker__segment--{each.status}"></span>
			{/each}
		</div>

		<details class="project-tracker__all">
			<summary>See every step</summary>
			<ol class="project-tracker__steps">
				{#each project.steps as each, index (each.state)}
					{@const text = detail(each)}
					<li
						class="project-tracker__step project-tracker__step--{each.status}"
						aria-current={each.status === 'current' ? 'step' : undefined}
					>
						<span class="project-tracker__marker" aria-hidden="true">
							{#if each.status === 'done'}
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html checkIcon}
							{:else}
								{index + 1}
							{/if}
						</span>
						<span class="project-tracker__copy">
							<span class="project-tracker__label">
								{PROJECT_STATE_LABEL[each.state]}
								<span class="project-tracker__hidden"
									>— {each.status === 'done'
										? 'done'
										: each.status === 'current'
											? 'current step'
											: 'still to come'}</span
								>
							</span>
							{#if text}<span class="project-tracker__date">{text}</span>{/if}
						</span>
					</li>
				{/each}
			</ol>
		</details>
	</div>
</SectionBlock>

<style lang="scss">
	.project-tracker {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__now {
			display: grid;
			gap: var(--space-smaller);

			p:not(.project-tracker__note) {
				margin: 0;
				color: var(--color-text);
				line-height: var(--typography--lineHeight-base);
			}
		}

		&__eyebrow {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		&__state {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			line-height: var(--typography--lineHeight-tight);
		}

		&__note {
			margin: 0;
			padding: var(--space-small) var(--space-slim);
			border-left: 3px solid var(--color-informative);
			border-radius: var(--radius-small);
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__bar {
			display: flex;
			gap: var(--space-smallest);
		}

		&__segment {
			flex: 1 1 0;
			height: 6px;
			border-radius: var(--radius-small);
			background: var(--color-border);

			&--done {
				background: var(--color-success);
			}

			// Under way: half filled, so it reads apart from the finished steps.
			&--current {
				background: linear-gradient(
					90deg,
					var(--color-success) 0 50%,
					var(--color-success--surface) 50% 100%
				);
				box-shadow: inset 0 0 0 1px var(--color-success);
			}
		}

		&__all summary {
			width: fit-content;
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__steps {
			display: grid;
			margin: var(--space-base) 0 0;
			padding: 0;
			list-style: none;
		}

		&__step {
			position: relative;
			display: flex;
			gap: var(--space-slim);
			padding-bottom: var(--space-base);

			// The line joining each step to the next one.
			&:not(:last-child)::before {
				content: '';
				position: absolute;
				top: 28px;
				bottom: 4px;
				left: 13px;
				width: 2px;
				border-radius: var(--radius-small);
				background: var(--color-border);
			}

			&--done:not(:last-child)::before {
				background: var(--color-success);
			}
		}

		&__marker {
			display: grid;
			place-items: center;
			flex: none;
			width: 28px;
			height: 28px;
			border: var(--border-thick) solid var(--color-border);
			border-radius: 50%;
			background: var(--color-surface);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			.project-tracker__step--done & {
				border-color: var(--color-success);
				background: var(--color-success);
				color: var(--color-surface);
			}

			.project-tracker__step--current & {
				border-color: var(--color-interactive);
				background: var(--color-surface);
				color: var(--color-interactive);
				box-shadow: 0 0 0 3px var(--color-informative--surface);
			}
		}

		&__copy {
			display: grid;
			gap: 2px;
			padding-top: 4px;
		}

		&__label {
			color: var(--color-text--secondary);
			font-weight: 400;

			.project-tracker__step--done & {
				color: var(--color-text);
			}

			.project-tracker__step--current & {
				color: var(--color-heading);
				font-weight: 700;
			}
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		&__date {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
