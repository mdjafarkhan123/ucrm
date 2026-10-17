<script lang="ts">
	import { resolve } from '$app/paths';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import { formatWhole } from '$lib/home/format';
	import type { TodoColumn, TodoColumnKey } from '$lib/home/todo';

	// "To do": the work waiting at each stage, across the whole business, one column per area the person may
	// see. Every line opens that area's list. A column whose overview could not be read says so on its own and
	// offers Try again, and the other columns keep working.
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

	const uid = $props.id();
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<section class="home-todo" aria-labelledby="{uid}-title">
	<header class="home-todo__header">
		<h2 id="{uid}-title">To do</h2>
		<p>Work waiting at each stage, across the whole business</p>
	</header>
	<div class="home-todo__columns" style:--todo-columns={columns.length}>
		{#each columns as column (column.key)}
			<section class="home-todo__column" aria-labelledby="{uid}-{column.key}">
				<header class="home-todo__head">
					<span class={['home-todo__icon', `home-todo__icon--${column.key}`]} aria-hidden="true"
						>{@html icons[column.key]}</span
					>
					<h3 id="{uid}-{column.key}">{column.title}</h3>
					{#if column.total !== null && !failed.includes(column.key)}
						<span class="home-todo__chip">{column.total}</span>
					{/if}
				</header>
				{#if failed.includes(column.key)}
					<HomeCardState
						state="error"
						label={column.title.toLowerCase()}
						onretry={() => onretry?.(column.key)}
					/>
				{:else}
					<ul class="home-todo__lines">
						{#each column.lines as line (line.key)}
							<li>
								<a
									class={[
										'home-todo__line',
										line.alert && (line.count ?? 0) > 0 && 'home-todo__line--alert'
									]}
									href={listHref(column.key, line.key)}
									aria-label={line.count === null
										? `${line.label}: ${line.hint}`
										: `${line.label}: ${line.count === 0 ? 'none' : line.count}. ${line.hint}`}
								>
									<span class="home-todo__text">
										<span class="home-todo__label">
											{#if line.alert && (line.count ?? 0) > 0}<span
													class="home-todo__dot"
													aria-hidden="true"
												></span>{/if}{line.label}
										</span>
										<span class="home-todo__hint">{line.hint}</span>
									</span>
									<span class="home-todo__numbers">
										{#if line.count === null}
											<span class="home-todo__skeleton" aria-hidden="true"></span>
										{:else if line.count === 0}
											<span class="home-todo__none">None</span>
										{:else}
											<span class="home-todo__count">{line.count}</span>
											{#if line.valueMinor !== null}<span class="home-todo__value"
													>{formatWhole(line.valueMinor, currency, locale)}</span
												>{/if}
										{/if}
									</span>
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
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__header {
			display: grid;
			gap: 3px;
			padding: 18px var(--space-large) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
				letter-spacing: -0.3px;
			}
			p {
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}

		&__columns {
			display: grid;
			grid-template-columns: repeat(var(--todo-columns, 4), minmax(0, 1fr));
		}

		&__column {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 6px;
			padding: 18px 20px 10px;

			& + & {
				border-left: var(--border-base) solid var(--color-border);
			}
		}

		&__head {
			display: flex;
			align-items: center;
			gap: 10px;
			padding-bottom: 6px;

			h3 {
				color: var(--color-heading);
				font-size: 15px;
				font-weight: 700;
			}
		}

		&__icon {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&--requests {
				color: var(--color-request--onSurface);
				background: var(--color-request--surface);
			}
			&--quotes {
				color: var(--color-quote--onSurface);
				background: var(--color-quote--surface);
			}
			&--jobs {
				color: var(--color-job--onSurface);
				background: var(--color-job--surface);
			}
			&--invoices {
				color: var(--color-invoice--onSurface);
				background: var(--color-invoice--surface);
			}
		}

		&__chip {
			display: inline-flex;
			align-items: center;
			height: 20px;
			padding: 0 7px;
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-border);
			font-size: 11px;
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}

		&__lines {
			display: grid;
			gap: 6px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__line {
			display: flex;
			align-items: center;
			gap: 10px;
			padding: 10px;
			border-radius: var(--radius-base);
			color: inherit;
			text-decoration: none;
			transition: background var(--timing-quick, 0.15s) ease;

			&:hover {
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 1px;
			}
			&--alert {
				background: var(--color-critical--surface);

				&:hover {
					background: var(--color-critical--surface);
					filter: brightness(0.97);
				}
				.home-todo__label,
				.home-todo__count,
				.home-todo__value {
					color: var(--color-critical);
				}
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
			color: var(--color-heading);
			font-size: 13px;
			font-weight: 600;
		}
		&__dot {
			flex: 0 0 auto;
			width: 7px;
			height: 7px;
			border-radius: var(--radius-circle);
			background: var(--color-critical);
		}
		&__hint {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: 12px;
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__numbers {
			display: grid;
			flex: 0 0 auto;
			justify-items: end;
			gap: 2px;
		}
		&__count {
			color: var(--color-heading);
			font-size: 16px;
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
		&__none {
			color: var(--color-text--secondary);
			font-size: 13px;
			font-weight: 500;
		}
		&__value {
			color: var(--color-text--secondary);
			font-size: 12px;
			font-weight: 500;
			font-variant-numeric: tabular-nums;
		}
		&__skeleton {
			width: 24px;
			height: 16px;
			border-radius: var(--radius-small);
			background: var(--color-border);
		}
	}

	/* Narrower than the full-width layout, the columns pair up, then stack. */
	@container (max-width: 900px) {
		.home-todo__columns {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.home-todo__column:nth-child(odd) {
			border-left: 0;
		}
		.home-todo__column:nth-child(n + 3) {
			border-top: var(--border-base) solid var(--color-border);
		}
	}
	@container (max-width: 520px) {
		.home-todo__columns {
			grid-template-columns: minmax(0, 1fr);
		}
		.home-todo__column {
			border-left: 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
	}
</style>
