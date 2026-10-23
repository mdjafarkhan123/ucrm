<script lang="ts">
	import Popover from '$lib/components/ui/Popover.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { countryInSentence } from '$lib/components/communications/add-number/add-number';
	import type { BusinessDestination, DestinationEvent } from '$lib/jafar/texting-setup';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-2.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import circleOffIcon from '@tabler/icons/outline/circle-off.svg?raw';

	// Show its history (board `oCM6G`): one country's story for one business, newest first, from the ⋯ menu on
	// its countries card. The approved History pop-over (`e18rX`); the card already holds the events.
	let {
		row,
		organizationName,
		anchor,
		onClose
	}: {
		row: BusinessDestination;
		organizationName: string;
		anchor: HTMLElement | null;
		onClose: () => void;
	} = $props();

	const country = $derived(countryDisplayName(row.country));
	const title = $derived(`History of ${countryInSentence(row.country, country)}`);
	// The home country's first request is the business buying its first number, not someone asking.
	const firstAsk = $derived(row.history.findLast((event) => event.kind === 'requested'));

	const tones: Record<DestinationEvent['kind'], { icon: string; tone: string }> = {
		requested: { icon: messageIcon, tone: 'conversation' },
		switched_on: { icon: checkIcon, tone: 'success' },
		closed: { icon: banIcon, tone: 'critical' },
		turned_off: { icon: circleOffIcon, tone: 'inactive' }
	};

	function said(event: DestinationEvent): string {
		const note = event.note ? ` · ${event.note}` : '';
		if (event.kind === 'requested') {
			if (row.is_home && event === firstAsk) {
				return event.who ? `Came with ${event.who}’s first number` : 'Came with the first number';
			}
			return `Asked for by ${event.who ?? organizationName}`;
		}
		const who = event.who ?? 'Uplift';
		if (event.kind === 'switched_on') return `Turned on by ${who}`;
		if (event.kind === 'closed') return `Not turned on by ${who}${note}`;
		return `Turned off by ${who}${note}`;
	}

	const when = (at: string) =>
		new Date(at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
</script>

<Popover open {anchor} {title} icon={historyIcon} iconTone="inactive" {onClose}>
	{#if row.history.length}
		<ol class="country-history">
			{#each row.history as event (`${event.kind}-${event.at}`)}
				<li class="country-history__event">
					<IconTile icon={tones[event.kind].icon} tone={tones[event.kind].tone} size={24} />
					<span class="country-history__words">
						<span class="country-history__action">{said(event)}</span>
						<time class="country-history__when" datetime={event.at}>{when(event.at)}</time>
					</span>
				</li>
			{/each}
		</ol>
	{:else}
		<p class="country-history__empty">
			Nothing has happened to {countryInSentence(row.country, country)} here yet.
		</p>
	{/if}
</Popover>

<style lang="scss">
	.country-history {
		display: flex;
		flex-direction: column;
		min-width: 280px;
		margin: 0;
		padding: 0;
		list-style: none;

		&__event {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			&:first-child {
				padding-top: 0;
			}

			&:last-child {
				padding-bottom: 0;
			}
		}

		&__words {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__action {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			line-height: 1.3;
		}

		&__when,
		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
