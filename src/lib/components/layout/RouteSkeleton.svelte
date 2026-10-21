<script lang="ts">
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';

	// `list` and `record` take the layout of the page being opened (`concept.pen` → Batch 48 · Page loading), so
	// nothing moves when it arrives. Any other page keeps the plain header, summary cards and two panels.
	let { kind = 'plain' }: { kind?: 'list' | 'record' | 'plain' } = $props();

	const ROWS = [
		[224, 144],
		[168, 112],
		[252, 160],
		[196, 124],
		[224, 144],
		[168, 112],
		[252, 160],
		[196, 124]
	];
	const FACTS = [70, 90, 80, 56];
</script>

{#snippet bone(width: number | string, height: number, shape = 'text')}
	<span
		class={`skeleton route-skeleton__bone route-skeleton__bone--${shape}`}
		style:width={typeof width === 'number' ? `${width}px` : width}
		style:height={`${height}px`}
	></span>
{/snippet}

{#snippet cardHead(title: number)}
	<div class="route-skeleton__card-head">
		{@render bone(40, 40, 'tile')}
		<span class="route-skeleton__lines">
			{@render bone(title, 12)}
			{@render bone(220, 8)}
		</span>
	</div>
{/snippet}

{#snippet sideCard(body: boolean)}
	<div class="route-skeleton__card">
		<div class="route-skeleton__card-head route-skeleton__card-head--side">
			{@render bone(40, 40, 'tile')}
			<span class="route-skeleton__lines">
				{@render bone(100, 12)}
				{@render bone(140, 8)}
			</span>
		</div>
		{#if body}
			<div class="route-skeleton__side-body">
				{@render bone('100%', 10)}
				{@render bone('82%', 10)}
				{@render bone('62%', 10)}
			</div>
		{/if}
	</div>
{/snippet}

{#if kind === 'list'}
	<main class="route-skeleton" aria-busy="true" aria-label="Loading page">
		<header class="route-skeleton__page-head">
			{@render bone(40, 40, 'page-tile')}
			<span class="route-skeleton__lines route-skeleton__lines--grow">
				{@render bone(120, 24, 'page')}
				{@render bone(380, 12, 'page')}
			</span>
			{@render bone(36, 36, 'page-tile')}
			{@render bone(112, 40, 'page-tile')}
		</header>

		<section class="route-skeleton__stats" aria-label="Loading summary">
			{#each Array(4) as _, index (index)}
				<div class="route-skeleton__card route-skeleton__number">
					<div class="route-skeleton__number-top">
						{@render bone(32, 32, 'tile')}
						{@render bone(90 + index * 8, 10)}
					</div>
					{@render bone(64 + index * 8, 28)}
					{@render bone(120, 8)}
				</div>
			{/each}
		</section>

		<section class="route-skeleton__card" aria-label="Loading list">
			<div class="route-skeleton__card-head route-skeleton__card-head--wide">
				{@render bone(40, 40, 'tile')}
				<span class="route-skeleton__lines route-skeleton__lines--grow">
					{@render bone(140, 12)}
					{@render bone(220, 8)}
				</span>
				{@render bone(220, 36, 'tile')}
			</div>
			<div class="route-skeleton__head-row">
				{@render bone(16, 8)}
				{@render bone(70, 8)}
				<span class="route-skeleton__head-end">
					{@render bone(60, 8)}
					{@render bone(60, 8)}
					{@render bone(56, 8)}
				</span>
			</div>
			<div class="route-skeleton__rows">
				{#each ROWS as [first, second], index (index)}
					<div class="route-skeleton__row">
						{@render bone(32, 32, 'tile')}
						<span class="route-skeleton__lines route-skeleton__lines--grow">
							{@render bone(first, 10)}
							{@render bone(second, 8)}
						</span>
						{@render bone(72, 10)}
						{@render bone(64, 10)}
						{@render bone(56, 20, 'pill')}
					</div>
				{/each}
			</div>
		</section>
	</main>
{:else if kind === 'record'}
	<main class="route-skeleton" aria-busy="true" aria-label="Loading page">
		<div class="route-skeleton__crumb">
			{@render bone(24, 24, 'pill')}
			{@render bone(56, 8, 'page')}
			{@render bone(6, 6, 'pill')}
			{@render bone(120, 8, 'page')}
		</div>

		<div class="route-skeleton__columns">
			<div class="route-skeleton__main">
				<section class="route-skeleton__card route-skeleton__record" aria-label="Loading record">
					<div class="route-skeleton__record-top">
						<span class="route-skeleton__record-title">
							{@render bone(40, 40, 'tile')}
							{@render bone(76, 24, 'pill')}
							<span class="route-skeleton__record-actions">
								{@render bone(36, 36, 'tile')}
								{@render bone(36, 36, 'tile')}
								{@render bone(84, 36, 'tile')}
								{@render bone(128, 36, 'tile')}
							</span>
						</span>
						{@render bone(320, 26, 'tile')}
					</div>
					<div class="route-skeleton__client">
						{@render bone(36, 36, 'pill')}
						<span class="route-skeleton__lines">
							{@render bone(130, 10)}
							<span class="route-skeleton__client-contact">
								{@render bone(180, 8)}
								{@render bone(110, 8)}
								{@render bone(140, 8)}
							</span>
						</span>
					</div>
					<div class="route-skeleton__facts">
						{#each FACTS as width, index (index)}
							<span class="route-skeleton__lines">
								<span class="route-skeleton__fact-label">
									{@render bone(20, 20, 'tile')}
									{@render bone(width, 8)}
								</span>
								{@render bone(width + 40, 10)}
							</span>
						{/each}
					</div>
					<div class="route-skeleton__track">
						{#each Array(5) as _, index (index)}
							{#if index > 0}{@render bone(24, 2)}{/if}
							{@render bone(32, 32, 'tile')}
							{@render bone(60, 8)}
						{/each}
					</div>
				</section>

				<section class="route-skeleton__card" aria-label="Loading section">
					{@render cardHead(160)}
					<div class="route-skeleton__rows route-skeleton__rows--ruled">
						{#each ROWS.slice(0, 3) as [first, second], index (index)}
							<div class="route-skeleton__row">
								{@render bone(32, 32, 'tile')}
								<span class="route-skeleton__lines route-skeleton__lines--grow">
									{@render bone(first + 20, 10)}
									{@render bone(second, 8)}
								</span>
								{@render bone(40, 10)}
								{@render bone(72, 10)}
							</div>
						{/each}
					</div>
				</section>

				<section class="route-skeleton__card" aria-label="Loading section">
					{@render cardHead(160)}
				</section>
			</div>

			<div class="route-skeleton__side">
				<div class="route-skeleton__card route-skeleton__money">
					{@render bone(120, 12)}
					{@render bone(160, 28, 'tile')}
					{@render bone('100%', 10)}
					{#each [90, 70, 80] as width, index (index)}
						<span class="route-skeleton__money-row">
							{@render bone(width, 8)}
							{@render bone(56, 8)}
						</span>
					{/each}
				</div>
				{@render sideCard(true)}
				{@render sideCard(false)}
			</div>
		</div>
	</main>
{:else}
	<main class="route-skeleton" aria-busy="true" aria-label="Loading page">
		<header class="route-skeleton__header">
			<div class="route-skeleton__heading">
				<LoadingSkeleton variant="heading" label="Loading page title" />
				<LoadingSkeleton variant="text" label="Loading page summary" />
			</div>
			<LoadingSkeleton variant="button" label="Loading page action" />
		</header>

		<section class="route-skeleton__stats" aria-label="Loading summary">
			{#each Array(4) as _, index (index)}
				<LoadingSkeleton variant="card" label="Loading summary card" />
			{/each}
		</section>

		<section class="route-skeleton__panels" aria-label="Loading page content">
			<LoadingSkeleton variant="card" label="Loading primary content" />
			<LoadingSkeleton variant="card" label="Loading secondary content" />
		</section>
	</main>
{/if}

<style lang="scss">
	.route-skeleton {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}

	// Shapes sit on a card by default; on the page colour they take the stronger grey.
	.route-skeleton__bone {
		flex: 0 0 auto;
		max-width: 100%;
		min-height: 0;

		&--text {
			border-radius: var(--radius-small);
		}
		&--tile {
			border-radius: var(--radius-base);
		}
		&--pill {
			border-radius: var(--radius-circle);
		}
		&--page,
		&--page-tile {
			background: linear-gradient(
				90deg,
				var(--color-border--interactive) 25%,
				var(--color-border) 50%,
				var(--color-border--interactive) 75%
			);
			background-size: 400% 100%;
		}
		&--page {
			border-radius: var(--radius-small);
		}
		&--page-tile {
			border-radius: var(--radius-base);
		}
	}

	.route-skeleton__lines {
		display: grid;
		gap: var(--space-small);
		min-width: 0;

		&--grow {
			flex: 1 1 auto;
		}
	}

	.route-skeleton__card {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
	}

	.route-skeleton__page-head {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.route-skeleton__number {
		display: grid;
		gap: var(--space-slim);
		padding: var(--space-base);
	}
	.route-skeleton__number-top {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	.route-skeleton__card-head {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-base) var(--space-medium);
		border-bottom: var(--border-base) solid var(--color-border);

		&--wide {
			border-bottom: 0;
		}
		&--side {
			padding: var(--space-slim) var(--space-base);
		}
	}

	.route-skeleton__head-row {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-medium);
		border-block: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
	.route-skeleton__head-end {
		display: flex;
		gap: var(--space-base);
		margin-left: auto;
	}

	.route-skeleton__rows {
		display: grid;
		padding: var(--space-small);
	}
	.route-skeleton__row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: var(--space-slim) var(--space-base);
	}

	.route-skeleton__crumb {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		width: fit-content;
		padding: var(--space-smaller) var(--space-slim) var(--space-smaller) var(--space-smaller);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-circle);
		background: var(--color-surface);
	}

	.route-skeleton__columns {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 336px;
		gap: var(--space-large);
		align-items: start;
	}
	.route-skeleton__main,
	.route-skeleton__side {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}

	.route-skeleton__record-top {
		display: grid;
		gap: var(--space-slim);
		padding: var(--space-medium);
		background: var(--color-surface--background--subtle);
	}
	.route-skeleton__record-title {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}
	.route-skeleton__record-actions {
		display: flex;
		gap: var(--space-small);
		margin-left: auto;
	}
	.route-skeleton__client {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-base) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
	}
	.route-skeleton__client-contact {
		display: flex;
		gap: var(--space-base);
	}
	.route-skeleton__facts {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
		padding: var(--space-base) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
	}
	.route-skeleton__fact-label {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.route-skeleton__track {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
	.route-skeleton__money,
	.route-skeleton__side-body {
		display: grid;
		gap: var(--space-slim);
		padding: var(--space-medium);
	}
	.route-skeleton__side-body {
		gap: var(--space-small);
		padding: var(--space-base);
	}
	.route-skeleton__money-row {
		display: flex;
		justify-content: space-between;
	}

	.route-skeleton__header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.route-skeleton__heading {
		display: grid;
		gap: var(--space-small);
		flex: 1;
		min-width: 0;
	}

	.route-skeleton__stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.route-skeleton__panels {
		display: grid;
		grid-template-columns: minmax(0, 1.35fr) minmax(380px, 1fr);
		gap: var(--space-base);
	}

	@media (max-width: 1100px) {
		.route-skeleton__columns {
			grid-template-columns: 1fr;
		}

		.route-skeleton__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}

		.route-skeleton__panels {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 639px) {
		.route-skeleton__header {
			align-items: stretch;
			flex-direction: column;
		}

		.route-skeleton__stats {
			grid-template-columns: 1fr;
		}
	}
</style>
