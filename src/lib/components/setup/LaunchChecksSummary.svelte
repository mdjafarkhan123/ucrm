<script lang="ts">
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import minusIcon from '@tabler/icons/outline/circle-minus.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import {
		LAUNCH_CHECK_TITLE,
		launchCheckWaitingLabel,
		launchChecklistFrom,
		launchWaitLine
	} from '$lib/setup/launch-checks';

	// Client onboarding E5 (plan §6): what Uplift checked before asking for launch approval, as kept with the
	// request — shown to the approver beside the approve box, on the Setup page and the private link page. A line
	// waiting on an outside company says so and is never shown as done. Nothing shows for a request without a list.
	let { checks, askedAt }: { checks: unknown; askedAt: string } = $props();

	const checklist = $derived(launchChecklistFrom(checks));
	const day = $derived(
		new Date(askedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'long' })
	);
</script>

{#if checklist && checklist.lines.length}
	<div class="launch-checks-summary">
		<h3 class="launch-checks-summary__title">What Uplift checked before asking ({day})</h3>
		<ul class="launch-checks-summary__list">
			{#each checklist.lines as line (line.key)}
				<li
					class="launch-checks-summary__line"
					class:launch-checks-summary__line--waiting={line.state === 'waiting'}
					class:launch-checks-summary__line--skipped={line.state === 'not_applicable'}
				>
					<span class="launch-checks-summary__icon" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -- a bundled Tabler icon -->
						{@html line.state === 'waiting'
							? hourglassIcon
							: line.state === 'not_applicable'
								? minusIcon
								: checkIcon}
					</span>
					<span>
						{LAUNCH_CHECK_TITLE[line.key]}
						<span class="launch-checks-summary__state">
							{#if line.state === 'waiting'}
								— not checked yet: {launchCheckWaitingLabel(line.waiting_on).toLowerCase()}
							{:else if line.state === 'not_applicable'}
								— doesn’t apply{line.reason ? `: ${line.reason}` : ''}
							{/if}
						</span>
					</span>
				</li>
			{/each}
		</ul>
		{#if checklist.waits.length}
			<p class="launch-checks-summary__waits-title">Still waiting on others</p>
			<ul class="launch-checks-summary__waits">
				{#each checklist.waits as wait (wait.key)}
					<li>{launchWaitLine(wait)}</li>
				{/each}
			</ul>
			<p class="launch-checks-summary__note">
				These are up to outside companies, and they don’t hold up your approval. Uplift keeps you
				posted on each one.
			</p>
		{/if}
	</div>
{/if}

<style lang="scss">
	.launch-checks-summary {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__list,
		&__waits {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__line {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			color: var(--color-text);
		}

		&__icon {
			display: inline-flex;
			flex: none;
			color: var(--color-success);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__line--waiting &__icon {
			color: var(--color-warning);
		}

		&__line--skipped &__icon {
			color: var(--color-text--secondary);
		}

		&__state {
			color: var(--color-text--secondary);
		}

		&__waits-title {
			margin: var(--space-smaller) 0 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__waits {
			padding-left: var(--space-base);
			list-style: disc;
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
