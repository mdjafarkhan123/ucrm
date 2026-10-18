<script lang="ts">
	import { resolve } from '$app/paths';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import { formatWhole } from '$lib/home/format';
	import type { TodoColumn, TodoColumnKey } from '$lib/home/todo';

	// "To do": the work waiting at each stage, across the whole business, one card per area the person may
	// see. Every line opens that area's list. A card whose overview could not be read says so on its own and
	// offers Try again, and the other cards keep working.
	let {
		columns,
		failed = [],
		currency = 'USD',
		locale = 'en-US',
		onretry
	}: {
		columns: TodoColumn[];
		failed?: TodoColumnKey[];
		currency?: string;
		locale?: string;
		onretry?: (key: TodoColumnKey) => void;
	} = $props();

	const tones: Record<TodoColumnKey, string> = {
		requests: 'request',
		quotes: 'quote',
		jobs: 'job',
		invoices: 'invoice'
	};
	const icons: Record<TodoColumnKey, string> = {
		requests: inboxIcon,
		quotes: fileTextIcon,
		jobs: hammerIcon,
		invoices: receiptIcon
	};

	function listBase(key: TodoColumnKey): string {
		switch (key) {
			case 'requests':
				return resolve('/(app)/requests');
			case 'quotes':
				return resolve('/(app)/quotes');
			case 'jobs':
				return resolve('/(app)/jobs');
			default:
				return resolve('/(app)/invoices');
		}
	}

	function listHref(key: TodoColumnKey, status: string) {
		return `${listBase(key)}?status=${status}`;
	}

	// The quiet line under each card's title: what the Invoices card still has to collect where this reader
	// may see that money, otherwise how many records wait in the card.
	function columnHint(column: TodoColumn): string | null {
		if (column.total === null) return null;
		if (column.key === 'invoices') {
			const owed = column.lines
				.filter((line) => line.key !== 'draft')
				.map((line) => line.valueMinor);
			if (owed.every((value) => value !== null))
				return `${formatWhole(
					owed.reduce<number>((sum, value) => sum + (value ?? 0), 0),
					currency,
					locale
				)} to collect`;
		}
		return `${column.total} waiting`;
	}

	const uid = $props.id();
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<section class="home-todo" aria-labelledby="{uid}-title">
	<header class="home-todo__header">
		<h2 id="{uid}-title">To do</h2>
		<p>Across the whole business</p>
	</header>
	<div class="home-todo__columns" style:--todo-columns={columns.length}>
		{#each columns as column (column.key)}
			<section class="home-todo__column" aria-labelledby="{uid}-{column.key}">
				<CardHeader
					id="{uid}-{column.key}"
					level={3}
					title={column.title}
					hint={failed.includes(column.key) ? null : columnHint(column)}
					icon={icons[column.key]}
					tone={tones[column.key]}
				>
					{#snippet actions()}
						<a
							class="home-todo__open"
							href={listBase(column.key)}
							aria-label="Open {column.title.toLowerCase()}"
							title="Open {column.title.toLowerCase()}">{@html arrowUpRightIcon}</a
						>
					{/snippet}
				</CardHeader>
				{#if failed.includes(column.key)}
					<HomeCardState
						state="error"
						label={column.title.toLowerCase()}
						onretry={() => onretry?.(column.key)}
					/>
				{:else}
					<ul class="home-todo__lines">
						{#each column.lines as line (line.key)}
							{@const waiting = (line.count ?? 0) > 0}
							<li>
								<a
									class="home-todo__line"
									href={listHref(column.key, line.key)}
									aria-label={line.count === null
										? `${line.label}: ${line.hint}`
										: `${line.label}: ${line.count === 0 ? 'none' : line.count}. ${line.hint}`}
								>
									<span class="home-todo__text">
										<span class="home-todo__label">
											{#if waiting && line.tone !== 'neutral'}<span
													class="home-todo__dot home-todo__dot--{line.tone}"
													aria-hidden="true"
												></span>{/if}{line.label}
										</span>
										<span class="home-todo__meta"
											>{line.valueMinor !== null && waiting
												? formatWhole(line.valueMinor, currency, locale)
												: line.hint}</span
										>
									</span>
									{#if line.count === null}
										<span class="home-todo__skeleton" aria-hidden="true"></span>
									{:else if line.count === 0}
										<span class="home-todo__none">None</span>
									{:else}
										<span class="home-todo__count home-todo__count--{line.tone}">{line.count}</span>
									{/if}
								</a>
							</li>
						{/each}
					</ul>
				{/if}
			</section>
		{/each}
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->

<style lang="scss">
	.home-todo {
		container-type: inline-size;
		display: grid;
		min-width: 0;
		gap: var(--space-base);

		&__header {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-slim);

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
			}
			p {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-label);
			}
		}

		&__columns {
			display: grid;
			grid-template-columns: repeat(var(--todo-columns, 4), minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__column {
			display: flex;
			min-width: 0;
			flex-direction: column;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__open {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 28px;
			height: 28px;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			transition: background var(--timing-quick, 0.15s) ease;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&:hover {
				color: var(--color-icon);
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__lines {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding: var(--space-medium);
			list-style: none;
		}

		&__line {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			min-height: 52px;
			padding: 0 10px 0 12px;
			border-radius: var(--radius-base);
			color: inherit;
			text-decoration: none;
			background: var(--color-surface--background--subtle);
			transition: background var(--timing-quick, 0.15s) ease;

			&:hover {
				background: var(--color-surface--background--subtle--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__text {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;
		}
		&__label {
			display: flex;
			align-items: center;
			gap: 6px;
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			white-space: nowrap;
		}
		&__dot {
			flex: 0 0 auto;
			width: 6px;
			height: 6px;
			border-radius: var(--radius-circle);

			@each $tone in success, warning, critical, informative {
				&--#{$tone} {
					background: var(--color-#{$tone});
				}
			}
		}
		&__meta {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__count {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			min-width: 26px;
			height: 26px;
			padding: 0 9px;
			border-radius: var(--radius-circle);
			font-size: var(--typography--fontSize-label);
			font-weight: 700;
			font-variant-numeric: tabular-nums;

			&--neutral {
				border: var(--border-base) solid var(--color-border);
				color: var(--color-heading);
				background: var(--color-surface);
			}
			@each $tone in success, warning, critical, informative {
				&--#{$tone} {
					color: var(--color-#{$tone}--onSurface);
					background: var(--color-#{$tone}--surface);
				}
			}
		}
		&__none {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}
		&__skeleton {
			width: 26px;
			height: 26px;
			border-radius: var(--radius-circle);
			background: var(--color-border);
		}
	}

	/* Narrower than the full-width layout, the cards pair up, then stack. */
	@container (max-width: 900px) {
		.home-todo__columns {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@container (max-width: 520px) {
		.home-todo__columns {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
