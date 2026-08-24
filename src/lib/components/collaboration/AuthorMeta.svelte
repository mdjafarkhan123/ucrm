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
		size = 'small'
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
		<span class="author-meta__name">{displayName}</span>
		<span class="author-meta__time" title={exactTime(timestamp)}
			>{relativeTime(timestamp)}{suffix ? ` · ${suffix}` : ''}</span
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

		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__time {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}
</style>
