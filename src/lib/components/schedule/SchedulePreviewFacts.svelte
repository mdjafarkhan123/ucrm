<script lang="ts">
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
			<span class="preview-facts__icon" aria-hidden="true">{@html icons[fact.kind]}</span>
			<div class="preview-facts__text">
				<dt>{fact.label}</dt>
				<dd class:preview-facts__warn={fact.warn}>{fact.value}</dd>
			</div>
		</div>
	{/each}
</dl>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.preview-facts {
		display: flex;
		flex-direction: column;
		gap: 10px;
		width: 100%;
		margin: 0;
	}

	.preview-facts__row {
		display: flex;
		align-items: flex-start;
		gap: 10px;
	}

	.preview-facts__icon {
		display: inline-flex;
		flex-shrink: 0;
		margin-top: 1px;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.preview-facts__text {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
	}

	dt {
		color: var(--color-text--secondary);
		font-size: 11.5px;
		line-height: 1.3;
	}

	dd {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		line-height: 1.35;
		overflow-wrap: anywhere;
		white-space: pre-wrap;
	}

	.preview-facts__warn {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}
</style>
