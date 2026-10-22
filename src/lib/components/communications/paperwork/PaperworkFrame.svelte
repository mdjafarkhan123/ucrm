<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import ImportStepper from '$lib/components/imports/ImportStepper.svelte';
	import PaperworkFlag from './PaperworkFlag.svelte';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
	import filePlusIcon from '@tabler/icons/outline/file-plus.svg?raw';
	import flagIcon from '@tabler/icons/outline/flag.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import filesIcon from '@tabler/icons/outline/files.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';

	// The setup-steps frame of New paperwork and an opened set (`concept.pen` board `A0URqF`): the breadcrumb,
	// the header with its actions at the right, the step track while the set is being filled in, then the body.
	let {
		crumb,
		title,
		description,
		flag,
		step,
		stepHints,
		actions,
		children
	}: {
		/** The breadcrumb's last step. */
		crumb: string;
		title: string;
		description?: string;
		/** A country code: an opened set shows its 40 flag where a new one shows the conversation tile. */
		flag?: string;
		/** The current step, 1 to 4, or null where no step track shows. */
		step: number | null;
		/** The quiet line under each step's name. */
		stepHints?: [string, string, string, string];
		actions?: Snippet;
		children: Snippet;
	} = $props();

	const steps = $derived(
		[
			{ title: 'Country and kind', icon: flagIcon },
			{ title: 'Business details', icon: buildingIcon },
			{ title: 'Documents', icon: filesIcon },
			{ title: 'Check and send', icon: sendIcon }
		].map((item, index) => ({
			n: index + 1,
			...item,
			hint: index + 1 === step ? 'You are here' : (stepHints?.[index] ?? '')
		}))
	);
</script>

<div class="paperwork-frame">
	<Breadcrumbs
		items={[
			{ label: 'Settings', href: resolve('/(app)/settings') },
			{
				label: 'Phone & SMS',
				href: resolve('/(app)/settings/communications/sms'),
				icon: messageIcon
			},
			{
				label: 'Number paperwork',
				href: resolve('/(app)/settings/communications/sms/paperwork'),
				icon: fileCheckIcon
			},
			{ label: crumb, icon: filePlusIcon }
		]}
	/>

	<header class="paperwork-frame__head">
		{#if flag}
			<PaperworkFlag code={flag} size={40} />
		{:else}
			<IconTile icon={filePlusIcon} tone="conversation" />
		{/if}
		<div class="paperwork-frame__copy">
			<h1>{title}</h1>
			{#if description}<p>{description}</p>{/if}
		</div>
		{#if actions}<div class="paperwork-frame__actions">{@render actions()}</div>{/if}
	</header>

	{#if step !== null}
		<ImportStepper current={step} {steps} label="Paperwork steps" />
	{/if}

	{@render children()}
</div>

<style lang="scss">
	// One 760 column, blocks 24 apart (design skill `layout.md` → Setup steps).
	.paperwork-frame {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 760px;
		margin-inline: auto;
		padding-block: var(--space-large);
		padding-inline: var(--space-base);
		box-sizing: content-box;

		> :global(.breadcrumbs) {
			align-self: flex-start;
			margin-bottom: 0;
		}

		&__head {
			display: flex;
			align-items: center;
			gap: 14px;
		}

		&__copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: 2px;
			min-width: 0;

			h1 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				letter-spacing: -0.5px;
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
				line-height: 1.45;
			}
		}

		&__actions {
			display: flex;
			flex: none;
			align-items: center;
			gap: var(--space-slim);
		}
	}
</style>
