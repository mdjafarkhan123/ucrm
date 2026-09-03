<script lang="ts">
	import { Combobox } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Who is assigned, searched and picked the way Jobber's crew field works: avatar chips for who is already
	// on the visit, a search box beneath for adding more. Replaces a flat one-checkbox-per-member list, which
	// grows without bound once a crew passes a couple dozen names. Shared by the Schedule job draft and the
	// Job Visit dialog so both present the same picker. Fetches the assignable team itself, gated by `open` so
	// a closed dialog holds no query, the way ClientPicker owns its own client search.
	let {
		value = $bindable<string[]>([]),
		id,
		open,
		label = 'Assigned team'
	}: {
		value?: string[];
		id: string;
		/** The owning dialog's open state; the team list is only worth fetching while it is visible. */
		open: boolean;
		label?: string;
	} = $props();

	let query = $state('');
	let comboboxOpen = $state(false);

	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: open,
		staleTime: 5 * 60 * 1000
	}));
	const team = $derived<TeamMember[]>(teamQuery.data ?? []);

	const normalizedQuery = $derived(query.trim().toLowerCase());
	const filtered = $derived(
		normalizedQuery
			? team.filter((member) => (member.full_name ?? '').toLowerCase().includes(normalizedQuery))
			: team
	);
	const comboboxItems = $derived(
		filtered.map((member) => ({ value: member.id, label: member.full_name ?? 'A team member' }))
	);
	const selectedMembers = $derived(team.filter((member) => value.includes(member.id)));

	function focusSearch() {
		comboboxOpen = true;
	}

	function handleValueChange(next: string[]) {
		value = next;
	}

	// `query` only drives this component's own filtering -- it is never handed back to Combobox.Root, whose
	// own inputValue box runs selection-commit logic multi-select was never meant to share with a filter
	// box. Resetting it here, once a pick has landed, brings the full roster back for the next name without
	// touching that box or anything it feeds.
	$effect(() => {
		value;
		query = '';
	});

	function removeMember(memberId: string) {
		value = value.filter((entry) => entry !== memberId);
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="team-picker">
	<legend class="team-picker__legend">
		<span aria-hidden="true">{@html usersIcon}</span>
		{label}
	</legend>
	{#if teamQuery.isPending}
		<p class="team-picker__hint">Loading your team…</p>
	{:else if team.length === 0}
		<p class="team-picker__hint">No team members to assign yet.</p>
	{:else}
		{#if selectedMembers.length}
			<div class="team-picker__chips">
				{#each selectedMembers as member (member.id)}
					<span class="team-picker__chip">
						<Avatar id={member.id} name={member.full_name} src={member.avatar_url} size="small" />
						<span class="team-picker__chip-name">{member.full_name ?? 'A team member'}</span>
						<button
							type="button"
							class="team-picker__chip-remove"
							aria-label={`Remove ${member.full_name ?? 'team member'}`}
							onclick={() => removeMember(member.id)}
						>
							<span aria-hidden="true">{@html xIcon}</span>
						</button>
					</span>
				{/each}
			</div>
		{/if}
		<Combobox.Root
			type="multiple"
			{value}
			bind:open={comboboxOpen}
			items={comboboxItems}
			onValueChange={handleValueChange}
		>
			<div class="team-picker__control">
				<span class="team-picker__search-icon" aria-hidden="true">{@html searchIcon}</span>
				<Combobox.Input
					id={`${id}-search`}
					placeholder="Search team members"
					autocomplete="off"
					onfocus={focusSearch}
					onclick={focusSearch}
					oninput={(event) => {
						query = event.currentTarget.value;
						comboboxOpen = true;
					}}
				/>
			</div>
			<Combobox.Portal>
				<Combobox.Content
					class="team-picker__menu"
					data-elevation="elevated"
					align="start"
					sideOffset={4}
					collisionPadding={8}
				>
					<Combobox.Viewport class="team-picker__viewport">
						{#each filtered as member (member.id)}
							<Combobox.Item
								value={member.id}
								label={member.full_name ?? 'A team member'}
								class="team-picker__option"
							>
								<Avatar
									id={member.id}
									name={member.full_name}
									src={member.avatar_url}
									size="small"
								/>
								<span class="team-picker__option-name">{member.full_name ?? 'A team member'}</span>
								{#if value.includes(member.id)}<span class="team-picker__check" aria-hidden="true"
										>{@html checkIcon}</span
									>{/if}
							</Combobox.Item>
						{:else}
							<div class="team-picker__empty">
								{normalizedQuery
									? `No team members match “${query.trim()}”.`
									: 'No team members yet.'}
							</div>
						{/each}
					</Combobox.Viewport>
				</Combobox.Content>
			</Combobox.Portal>
		</Combobox.Root>
	{/if}
</fieldset>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.team-picker {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.team-picker__legend {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		padding: 0 var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	.team-picker__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.team-picker__chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.team-picker__chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smallest) var(--space-small) var(--space-smallest) var(--space-smaller);
		border-radius: var(--radius-large);
		background: var(--color-surface--active);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
	}

	.team-picker__chip-name {
		overflow: hidden;
		max-width: 160px;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.team-picker__chip-remove {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		&:hover {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			display: block;
			width: 12px;
			height: 12px;
		}
	}

	.team-picker__control {
		position: relative;
		display: flex;
		min-height: var(--space-largest);
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.team-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}

	.team-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: calc(var(--space-largest) - (var(--border-base) * 2));
		padding: var(--space-small) var(--space-base) var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
	}

	.team-picker__search-icon {
		position: absolute;
		left: var(--space-base);
		display: grid;
		width: 16px;
		height: 16px;
		place-items: center;
		color: var(--color-icon--secondary);
		pointer-events: none;
	}

	.team-picker__search-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	:global(.team-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(260px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.team-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}

	:global(.team-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}

	:global(.team-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	.team-picker__option-name {
		overflow: hidden;
		flex: 1;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.team-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	.team-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
</style>
