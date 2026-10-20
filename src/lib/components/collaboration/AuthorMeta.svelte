<script lang="ts">
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import type { Profile } from '$lib/collaboration/api';

	let {
		userId,
		profile,
		currentUserId,
		timestamp,
		suffix,
		fallbackName = 'Unknown',
		size = 'base'
	}: {
		userId: string | null;
		profile: Profile | undefined;
		currentUserId?: string;
		timestamp: string;
		suffix?: string;
		/**
		 * Who to name when there is no user behind this at all. `Unknown` fits a teammate who has left,
		 * but not something the customer did, so the caller says which one it is.
		 */
		fallbackName?: string;
		size?: 'small' | 'base';
	} = $props();

	let displayName = $derived(
		!userId
			? fallbackName
			: userId === currentUserId
				? 'You'
				: (profile?.full_name ?? 'Team member')
	);
</script>

<span class="author-meta">
	<Avatar id={userId ?? 'unknown'} name={profile?.full_name} src={profile?.avatar_url} {size} />
	<span class="author-meta__text">
		<span class="author-meta__name-row"
			><span class="author-meta__name">{displayName}</span>{#if suffix}<span
					class="author-meta__edited">{suffix === 'edited' ? 'Edited' : suffix}</span
				>{/if}</span
		>
		<button type="button" class="author-meta__time" aria-label={exactTime(timestamp)}
			>{relativeTime(timestamp)}<span class="author-meta__tooltip" role="tooltip"
				>{exactTime(timestamp)}</span
			></button
		>
	</span>
</span>

<style lang="scss">
	.author-meta {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;

		&__text {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 1px;
		}

		&__name-row {
			display: flex;
			align-items: center;
			gap: 6px;
			min-width: 0;
		}
		&__edited {
			flex: 0 0 auto;
			padding: 1px 5px;
			border-radius: var(--radius-small);
			background: var(--color-inactive--surface);
			color: var(--color-inactive--onSurface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
		}
		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__tooltip {
			display: none;
			position: absolute;
			z-index: var(--elevation-tooltip);
			bottom: calc(100% + 6px);
			left: 0;
			width: max-content;
			max-width: min(280px, 80vw);
			padding: 5px 8px;
			border-radius: var(--radius-tile-small);
			color: var(--color-text--reverse);
			background: var(--color-surface--reverse);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__time:hover &__tooltip,
		&__time:focus-visible &__tooltip {
			display: block;
		}
		&__time {
			padding: 0;
			border: 0;
			background: transparent;
			font-family: inherit;
			text-align: left;
			cursor: help;
			position: relative;
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
				border-radius: var(--radius-small);
			}
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
