<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';

	// The rules a business should know before relying on Messenger (board `tEAXY`): Meta's 24-hour window, new
	// people becoming leads, and history surviving a disconnect.
	const facts = [
		{
			icon: clockIcon,
			tone: 'time',
			title: 'Reply within 24 hours',
			line: "Meta only lets businesses answer within 24 hours of a customer's last message."
		},
		{
			icon: userPlusIcon,
			tone: 'client',
			title: 'New people become leads',
			line: 'Someone new is added as a lead. You can link them to an existing client.'
		},
		{
			icon: archiveIcon,
			tone: 'inactive',
			title: 'Disconnecting keeps history',
			line: 'Old conversations stay. Reconnect and the same threads carry on.'
		}
	];
</script>

<section class="good-to-know" aria-labelledby="messenger-good-to-know">
	<h2 id="messenger-good-to-know" class="good-to-know__label">Good to know</h2>
	{#each facts as fact (fact.title)}
		<div class="good-to-know__row">
			<IconTile icon={fact.icon} tone={fact.tone} size={24} />
			<div class="good-to-know__text">
				<h3>{fact.title}</h3>
				<p>{fact.line}</p>
			</div>
		</div>
	{/each}
</section>

<style lang="scss">
	.good-to-know {
		display: grid;
		gap: 14px;
		padding: var(--space-medium);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
			letter-spacing: 0.4px;
			text-transform: uppercase;
		}
		&__row {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
		}
		&__text {
			display: grid;
			gap: 2px;

			h3 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
			p {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
				line-height: 1.45;
			}
		}
	}
</style>
