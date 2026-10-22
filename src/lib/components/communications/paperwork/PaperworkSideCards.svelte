<script lang="ts">
	import { resolve } from '$app/paths';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { ReusedDetails } from '$lib/communications/number-paperwork';
	import routeIcon from '@tabler/icons/outline/route.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import rosetteIcon from '@tabler/icons/outline/rosette-discount-check.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';

	// The Number paperwork page's side column (`concept.pen` board `A0URqF`): how paperwork works, and the
	// texting registration details a new set starts from.
	let { reused }: { reused: ReusedDetails | null } = $props();

	const STEPS = [
		['Fill in your details', 'We fill in what you already told us for texting.'],
		['Add the documents', 'Usually a registration extract and a proof of address.'],
		['The phone company checks it', 'Usually 1 to 5 business days. The answer shows here.'],
		['Buy your number', 'Approved paperwork works for more numbers in that country.']
	] as const;

	const facts = $derived(
		reused
			? [
					{ icon: rosetteIcon, tone: 'client', label: 'Legal name', value: reused.business_name },
					{
						icon: hashIcon,
						tone: 'inactive',
						label: 'Registration number',
						value: reused.registration_number
					},
					{ icon: mapPinIcon, tone: 'client', label: 'Business address', value: reused.address },
					{ icon: userIcon, tone: 'informative', label: 'Person in charge', value: reused.person }
				]
			: []
	);
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="paperwork-side">
	<section class="paperwork-side__card" aria-labelledby="paperwork-how">
		<CardHeader
			id="paperwork-how"
			title="How it works"
			hint="About 10 minutes of your time"
			icon={routeIcon}
			tone="informative"
			compact
		/>
		<ol class="paperwork-side__steps">
			{#each STEPS as [title, hint], index (title)}
				<li class="paperwork-side__step">
					<span class="paperwork-side__number">{index + 1}</span>
					<span class="paperwork-side__step-copy">
						<strong>{title}</strong>
						<span>{hint}</span>
					</span>
				</li>
			{/each}
		</ol>
	</section>

	<section class="paperwork-side__card" aria-labelledby="paperwork-reused">
		<CardHeader
			id="paperwork-reused"
			title="Details we reuse"
			hint="From your texting registration"
			icon={buildingIcon}
			tone="client"
			compact
		/>
		<dl class="paperwork-side__facts">
			{#each facts as fact (fact.label)}
				<div class="paperwork-side__fact">
					<IconTile icon={fact.icon} tone={fact.tone} size={32} />
					<span class="paperwork-side__fact-copy">
						<dt>{fact.label}</dt>
						<dd class={fact.value ? undefined : 'paperwork-side__fact-empty'}>
							{fact.value ?? 'Not given yet'}
						</dd>
					</span>
				</div>
			{/each}
		</dl>
		<a class="paperwork-side__link" href={resolve('/(app)/settings/communications/sms')}>
			Change them in Phone &amp; SMS
			<span aria-hidden="true">{@html arrowUpRightIcon}</span>
		</a>
	</section>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-side {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		min-width: 0;

		&__card {
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__steps {
			display: flex;
			flex-direction: column;
			gap: var(--space-medium);
			margin: 0;
			padding: var(--space-base) var(--space-medium) var(--space-medium);
			list-style: none;
		}

		&__step {
			position: relative;
			display: flex;
			gap: var(--space-slim);

			// The line that joins one numbered circle to the next.
			&:not(:last-child)::after {
				content: '';
				position: absolute;
				top: 28px;
				bottom: calc(-1 * var(--space-medium));
				left: 13px;
				width: var(--border-thick);
				background: var(--color-informative--surface-edge);
			}
		}

		&__number {
			position: relative;
			z-index: 1;
			display: grid;
			flex: none;
			place-items: center;
			width: 28px;
			height: 28px;
			border: var(--border-base) solid var(--color-informative--surface-edge);
			border-radius: var(--radius-circle);
			background: var(--color-informative--surface);
			color: var(--color-informative);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 700;
		}

		&__step-copy {
			display: grid;
			gap: 2px;
			padding-top: 4px;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				line-height: var(--typography--lineHeight-large);
			}
		}

		&__facts {
			margin: 0;
		}

		&__fact {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__fact-copy {
			display: grid;
			gap: 2px;
			min-width: 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
				overflow-wrap: anywhere;
			}
		}

		&__fact-empty {
			color: var(--color-text--secondary) !important;
			font-weight: 500 !important;
		}

		&__link {
			display: flex;
			align-items: center;
			gap: 6px;
			padding: var(--space-slim) var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: -2px;
			}

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}
	}
</style>
