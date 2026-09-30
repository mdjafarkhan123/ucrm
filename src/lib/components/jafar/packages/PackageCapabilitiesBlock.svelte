<script lang="ts">
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { missingRequirements, type CapabilityReference } from '$lib/jafar/packages';

	// What the package lets a contractor use. Core capabilities come with every package; Jafar chooses the
	// extras. A capability that needs another one (website chat needs the shared inbox) is explained, with
	// a button that includes what is missing — publishing refuses a package that leaves it out (P7).
	let {
		capabilities,
		selected = $bindable()
	}: {
		capabilities: CapabilityReference[];
		selected: string[];
	} = $props();

	const core = $derived(capabilities.filter((capability) => capability.kind === 'core'));
	const optional = $derived(capabilities.filter((capability) => capability.kind !== 'core'));
	const missing = $derived(missingRequirements(selected, capabilities));

	function labelOf(key: string) {
		return capabilities.find((capability) => capability.key === key)?.label ?? key;
	}

	function toggle(key: string, checked: boolean) {
		selected = checked ? [...selected, key] : selected.filter((selectedKey) => selectedKey !== key);
	}

	function include(keys: string[]) {
		selected = [...new Set([...selected, ...keys])];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="App features"
	form
	id="package-capabilities"
	hint="Only features marked ready can be sold. Others can stay in a draft, but the package cannot be published with them."
>
	<div class="package-capabilities">
		<div class="package-capabilities__group">
			<h3 class="package-capabilities__heading">In every package</h3>
			<ul class="package-capabilities__core">
				{#each core as capability (capability.key)}
					<li>
						<span class="package-capabilities__check" aria-hidden="true">{@html checkIcon}</span>
						{capability.label}
					</li>
				{/each}
			</ul>
		</div>

		<div class="package-capabilities__group">
			<h3 class="package-capabilities__heading">Extras</h3>

			{#each missing as entry (entry.capability.key)}
				<div class="package-capabilities__banner" role="status">
					<span class="package-capabilities__banner-icon" aria-hidden="true">{@html linkIcon}</span>
					<p>
						{entry.capability.label} needs {entry.missing
							.map((capability) => capability.label)
							.join(' and ')}
						to work. Include it, or remove {entry.capability.label}.
					</p>
					<Button
						size="small"
						variant="secondary"
						onclick={() => include(entry.missing.map((capability) => capability.key))}
						>Include {entry.missing.map((capability) => capability.label).join(' and ')}</Button
					>
				</div>
			{/each}

			<ul class="package-capabilities__extras">
				{#each optional as capability (capability.key)}
					<li class="package-capabilities__extra">
						<Checkbox
							id={`package-capability-${capability.key}`}
							label={capability.label}
							description={capability.requires.length
								? `${capability.description}. Needs ${capability.requires.map(labelOf).join(' and ')}.`
								: capability.description}
							checked={selected.includes(capability.key)}
							onchange={(checked) => toggle(capability.key, checked)}
						/>
						{#if capability.sellable}
							<Badge status="success" size="small">Ready</Badge>
						{:else if capability.kind === 'planned'}
							<Badge status="inactive" size="small">Planned</Badge>
						{:else}
							<Badge status="warning" size="small">Not ready to sell</Badge>
						{/if}
					</li>
				{/each}
			</ul>
		</div>
	</div>
</SectionBlock>

<style lang="scss">
	.package-capabilities {
		display: grid;
		gap: var(--space-large);

		&__group {
			display: grid;
			gap: var(--space-slim);
		}

		&__heading {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.02em;
			text-transform: uppercase;
		}

		&__core {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
			gap: var(--space-small) var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-text);
			}
		}

		&__check {
			display: inline-flex;
			color: var(--color-success);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__extras {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__extra {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-slim) 0;
			border-top: var(--border-base) solid var(--color-border);

			&:first-child {
				border-top: 0;
			}
		}

		&__banner {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-slim);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);

			p {
				flex: 1 1 240px;
				margin: 0;
				line-height: var(--typography--lineHeight-base);
			}
		}

		&__banner-icon {
			display: inline-flex;

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
	}
</style>
