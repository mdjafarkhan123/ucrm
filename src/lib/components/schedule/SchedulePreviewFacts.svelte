<script lang="ts">
	import { initials } from '$lib/collaboration/format';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import calendarTimeIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import alignLeftIcon from '@tabler/icons/outline/align-left.svg?raw';

	// The facts a selected card gives, one per line: a small icon, what it is, and what it says. The three
	// previews (visit, assessment, event) share it so a When, a Team and a Where read the same everywhere.

	type Kind = 'when' | 'team' | 'where' | 'client' | 'details';

	let {
		facts
	}: {
		facts: {
			kind: Kind;
			label: string;
			value: string;
			people?: string[];
			/** Nobody is assigned, so the value is a warning rather than a plain answer. */
			warn?: boolean;
		}[];
	} = $props();

	const icons: Record<Kind, string> = {
		when: calendarTimeIcon,
		team: usersIcon,
		where: mapPinIcon,
		client: userIcon,
		details: alignLeftIcon
	};
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<dl class="preview-facts">
	{#each facts as fact (fact.kind)}
		<div class="preview-facts__row">
			<IconTile
				icon={icons[fact.kind]}
				tone={fact.kind === 'where' || fact.kind === 'client'
					? 'client'
					: fact.kind === 'details'
						? 'event'
						: 'time'}
				size={32}
			/>
			<div class="preview-facts__text" class:preview-facts__text--details={fact.kind === 'details'}>
				<dt>{fact.label}</dt>
				<dd class:preview-facts__warn={fact.warn}>
					{#if fact.people?.length}<span class="preview-facts__people" aria-hidden="true"
							>{#each fact.people as person, index (`${person}-${index}`)}<span
									>{initials(person)}</span
								>{/each}</span
						>{/if}{fact.value}
				</dd>
			</div>
		</div>
	{/each}
</dl>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.preview-facts {
		display: flex;
		flex-direction: column;
		gap: 14px;
		width: 100%;
		margin: 0;
	}

	.preview-facts__row {
		display: flex;
		align-items: flex-start;
		gap: 10px;
	}

	.preview-facts__text {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
	}

	dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: 1.3;
	}

	.preview-facts__people {
		display: inline-flex;
		vertical-align: middle;
		margin-right: var(--space-smaller);
		gap: var(--space-smallest);
		> span {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-circle);
			background: var(--color-heading);
			color: var(--color-surface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
		}
	}
	dd {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		line-height: 1.35;
		overflow-wrap: anywhere;
		white-space: pre-wrap;
	}

	.preview-facts__text--details dd {
		color: var(--color-text);
		font-weight: 400;
		line-height: 1.45;
	}
	.preview-facts__warn {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}
</style>
