<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	// "Someone saved first" on an open section: who changed it and when, and — once the person has looked —
	// what their version says. The section keeps the person's own changes meanwhile.
	let {
		who,
		when,
		theirs
	}: {
		who: string;
		when: string;
		/** What the other person changed, as short lines; null until the person asks to see it. */
		theirs: string[] | null;
	} = $props();
</script>

<div class="profile-conflict" role="alert">
	<IconTile icon={usersIcon} tone="critical" size={32} white />
	<div class="profile-conflict__copy">
		<p>{who} changed this section {when}. See their version before you save yours.</p>
		{#if theirs}
			<ul>
				{#each theirs as line (line)}<li>{line}</li>{/each}
			</ul>
		{/if}
	</div>
</div>

<style lang="scss">
	.profile-conflict {
		display: flex;
		gap: var(--space-slim);
		padding: var(--space-slim);
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
		border-radius: var(--radius-large);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		line-height: 1.4;

		&__copy {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
			padding-top: var(--space-smaller);

			p {
				margin: 0;
			}
			ul {
				margin: 0;
				padding-left: var(--space-base);
			}
		}
	}
</style>
