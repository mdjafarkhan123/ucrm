<script lang="ts">
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { languageName } from '$lib/communications/sms-opt-out-words';
	import { whenAsked, type OptOutTask, type TextingTask } from '$lib/jafar/texting-setup';
	import sortIcon from '@tabler/icons/outline/arrows-sort.svg?raw';
	import globeIcon from '@tabler/icons/outline/world.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import messageOffIcon from '@tabler/icons/outline/message-off.svg?raw';

	// The Texting setup queue card (board `v6Jtu`): every task for every business, oldest first. The open
	// task is tinted with a green bar down its left edge.
	let {
		tasks,
		optOutTasks,
		selectedId,
		onSelect
	}: {
		tasks: TextingTask[];
		/** Opt-out words tasks (Part 5d), in the same oldest-first list. */
		optOutTasks: OptOutTask[];
		selectedId: string | null;
		onSelect: (id: string) => void;
	} = $props();

	type Row = {
		id: string;
		flag: string;
		title: string;
		meta: string;
		kind: string;
		icon: string;
		at: string;
	};

	const rows = $derived(
		[
			...tasks.map((task): Row => ({
				id: task.id,
				flag: task.country,
				title: `Turn on ${countryDisplayName(task.country)}`,
				meta: `${task.organization_name} · asked ${whenAsked(task.requested_at)}`,
				kind: 'Twilio permission',
				icon: globeIcon,
				at: task.requested_at
			})),
			...optOutTasks.map((task): Row => ({
				id: task.id,
				flag: task.countries[0],
				title: `Add ${languageName(task.language)} opt-out words`,
				meta: `For ${task.countries.map(countryDisplayName).join(' and ')} · ${task.organization_name} · ${whenAsked(task.requested_at)}`,
				kind: 'Opt-out words',
				icon: messageOffIcon,
				at: task.requested_at
			}))
		].sort((a, b) => a.at.localeCompare(b.at))
	);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="task-queue" aria-labelledby="task-queue-title">
	<header class="task-queue__head">
		<h2 id="task-queue-title">To do</h2>
		<span class="task-queue__order">
			Oldest first <span aria-hidden="true">{@html sortIcon}</span>
		</span>
	</header>
	<ul class="task-queue__rows">
		{#each rows as row (row.id)}
			<li>
				<button
					type="button"
					class={['task-queue__row', row.id === selectedId && 'task-queue__row--open']}
					aria-current={row.id === selectedId ? 'true' : undefined}
					onclick={() => onSelect(row.id)}
				>
					<PaperworkFlag code={row.flag} />
					<span class="task-queue__copy">
						<strong>{row.title}</strong>
						<span>{row.meta}</span>
						<span class="task-queue__kind">
							<span aria-hidden="true">{@html row.icon}</span>
							{row.kind}
						</span>
					</span>
					<span class="task-queue__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
				</button>
			</li>
		{/each}
	</ul>
	<p class="task-queue__foot">
		<span aria-hidden="true">{@html infoIcon}</span>
		A business’s request lands here the moment it asks. Done tasks move to its Activity.
	</p>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.task-queue {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}
		}

		&__order {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			span {
				display: inline-flex;
				width: 14px;
				height: 14px;
			}
		}

		&__rows {
			flex: 1;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			position: relative;
			display: grid;
			grid-template-columns: 32px minmax(0, 1fr) 16px;
			align-items: start;
			column-gap: var(--space-slim);
			width: 100%;
			padding: 14px var(--space-base);
			border: 0;
			border-bottom: var(--border-base) solid var(--color-border);
			background: transparent;
			color: inherit;
			font: inherit;
			text-align: left;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: -2px;
			}

			&--open,
			&--open:hover {
				background: var(--color-surface--active);

				&::before {
					content: '';
					position: absolute;
					inset: 0 auto 0 0;
					width: 3px;
					background: var(--color-interactive);
				}

				.task-queue__chevron {
					color: var(--color-interactive);
				}
			}
		}

		&__copy {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			> span:not(.task-queue__kind) {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}

		&__kind {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			height: 24px;
			margin-top: var(--space-smaller);
			padding: 0 var(--space-small);
			border-radius: var(--radius-circle);
			background: var(--color-conversation--surface);
			color: var(--color-conversation--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			span {
				display: inline-flex;
				width: 12px;
				height: 12px;
			}
		}

		&__chevron {
			display: inline-flex;
			width: 16px;
			height: 16px;
			margin-top: 2px;
			color: var(--color-text--secondary);
		}

		&__foot {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);

			span {
				display: inline-flex;
				flex: none;
				width: 14px;
				height: 14px;
				color: var(--color-informative);
			}
		}
	}
</style>
