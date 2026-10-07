<script lang="ts">
	import { goto } from '$app/navigation';
	import { createQuery } from '@tanstack/svelte-query';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SettingsDestinationCard from '$lib/components/settings/SettingsDestinationCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import { jafarSettingsKey } from '$lib/jafar/query-keys';
	import {
		fetchOwnerSettings,
		searchSettings,
		settingsGroups,
		type SettingsDestination
	} from '$lib/jafar/owner-settings';

	// The directory is fixed, so every group and card draws at once; only the "needs attention" marks wait
	// for the saved values, and fill in when they arrive.
	const query = createQuery(() => ({ queryKey: jafarSettingsKey, queryFn: fetchOwnerSettings }));

	let search = $state('');
	const searching = $derived(search.trim() !== '');
	const groups = $derived(searchSettings(settingsGroups, search));
	const firstResult = $derived(groups[0]?.destinations[0]);

	function statusOf(destination: SettingsDestination) {
		return query.data ? destination.status?.(query.data) : undefined;
	}

	const needsAttention = $derived(
		settingsGroups.flatMap((group) =>
			group.destinations.filter((destination) => statusOf(destination) !== undefined)
		)
	);

	// Enter opens the best match, so "sender ⏎" goes straight to the setting.
	function openFirstResult(event: KeyboardEvent) {
		if (event.key !== 'Enter' || !searching || !firstResult) return;
		event.preventDefault();
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the directory's links are resolved where they are defined.
		void goto(firstResult.href);
	}
</script>

<svelte:head><title>Settings · Control Room</title></svelte:head>

<main class="jafar-settings">
	<PageHeader
		eyebrow="Control Room"
		title="Settings"
		description="How Uplift and the platform are set up — find a setting by what it does."
	/>

	<div class="jafar-settings__tools">
		<SearchInput
			id="settings-search"
			bind:value={search}
			placeholder="Search settings, like “sender” or “privacy”"
			ariaLabel="Search settings"
			class="jafar-settings__search"
			onkeydown={openFirstResult}
		/>
		{#if !searching}
			<nav class="jafar-settings__jump" aria-label="Settings groups">
				{#each settingsGroups as group (group.id)}
					<a href={`#${group.id}`}>{group.title}</a>
				{/each}
			</nav>
		{/if}
	</div>

	{#if !searching && needsAttention.length > 0}
		<Banner type="warning" icon={alertTriangleIcon}>
			<p class="jafar-settings__attention">
				{needsAttention.length === 1
					? '1 setting needs attention:'
					: `${needsAttention.length} settings need attention:`}
				{#each needsAttention as destination, index (destination.id)}
					<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- the directory's links are resolved where they are defined. -->
					<a href={destination.href}>{destination.title}</a>{index < needsAttention.length - 1
						? ', '
						: ''}
				{/each}
			</p>
		</Banner>
	{:else if query.isError && !query.data}
		<Banner type="notice">
			<p class="jafar-settings__attention">
				Could not check which settings need attention. Every setting still opens as normal.
			</p>
			{#snippet action()}
				<Button size="small" variant="secondary" onclick={() => query.refetch()}>Try again</Button>
			{/snippet}
		</Banner>
	{/if}

	{#if groups.length === 0}
		<EmptyState
			title={`No settings match “${search.trim()}”`}
			description="Try another word for what you want to change, like “email” or “payment”."
			icon={searchIcon}
		>
			{#snippet action()}
				<Button variant="secondary" onclick={() => (search = '')}>Clear search</Button>
			{/snippet}
		</EmptyState>
	{:else}
		<div class="jafar-settings__groups">
			{#each groups as group (group.id)}
				<SectionBlock
					title={group.title}
					hint={group.hint}
					icon={group.icon}
					id={group.id}
					level={2}
				>
					{#if group.destinations.length > 0}
						<div class="jafar-settings__grid">
							{#each group.destinations as destination (destination.id)}
								<SettingsDestinationCard
									href={destination.href}
									icon={destination.icon}
									title={destination.title}
									description={destination.description}
									status={statusOf(destination)}
								/>
							{/each}
						</div>
					{:else}
						<p class="jafar-settings__upcoming">{group.upcoming}</p>
					{/if}
				</SectionBlock>
			{/each}
		</div>
	{/if}
</main>

<style lang="scss">
	.jafar-settings {
		--section-block-notch: var(--color-surface);
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-large);
	}

	.jafar-settings__tools {
		position: sticky;
		top: var(--space-base);
		z-index: var(--elevation-base);
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.jafar-settings__tools :global(.jafar-settings__search) {
		flex: 1 1 280px;
		max-width: 420px;
	}

	.jafar-settings__jump {
		display: flex;
		min-width: 0;
		flex: 1 1 auto;
		gap: var(--space-smaller);
		overflow-x: auto;
		scrollbar-width: none;

		a {
			flex: 0 0 auto;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;
			white-space: nowrap;

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}

	.jafar-settings__attention {
		margin: 0;

		a {
			color: inherit;
			font-weight: 700;
		}
	}

	.jafar-settings__groups {
		display: flex;
		flex-direction: column;
		gap: var(--space-larger);
	}

	.jafar-settings__grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.jafar-settings__upcoming {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.jafar-settings__groups section[id]) {
		scroll-margin-top: calc(var(--space-largest) * 2);
	}

	@media (max-width: 1079px) {
		.jafar-settings__grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.jafar-settings {
			gap: var(--space-base);
		}

		.jafar-settings__tools {
			position: static;
		}

		.jafar-settings__tools :global(.jafar-settings__search) {
			max-width: none;
		}

		.jafar-settings__grid {
			grid-template-columns: 1fr;
		}
	}
</style>
