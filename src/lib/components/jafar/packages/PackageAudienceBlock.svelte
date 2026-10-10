<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import {
		experienceFitGaps,
		type CapabilityReference,
		type ExperienceReference,
		type IncludedService,
		type PackageService
	} from '$lib/jafar/packages';

	// Multi-industry foundation B2: the kinds of business that can buy this package. Everything in it must
	// fit each one; what does not is named here as Jafar edits, and publishing refuses it.
	let {
		experiences,
		capabilities,
		services,
		selectedCapabilities,
		includedServices,
		selected = $bindable()
	}: {
		experiences: ExperienceReference[];
		capabilities: CapabilityReference[];
		services: PackageService[];
		selectedCapabilities: string[];
		includedServices: IncludedService[];
		selected: string[];
	} = $props();

	const gaps = $derived(
		experienceFitGaps(
			{
				experience_keys: selected,
				capabilities: selectedCapabilities,
				included_services: includedServices
			},
			{ capabilities, services, experiences }
		)
	);

	function toggle(key: string, checked: boolean) {
		selected = checked
			? [...new Set([...selected, key])].sort()
			: selected.filter((selectedKey) => selectedKey !== key);
	}
</script>

<SectionBlock
	title="Who can buy it"
	form
	id="package-audience"
	hint="The kinds of business this package is sold to. Only these businesses see it on sign-up or can be moved onto it."
>
	<div class="package-audience">
		<ul class="package-audience__list">
			{#each experiences as experience (experience.key)}
				<li>
					<Checkbox
						id={`package-audience-${experience.key}`}
						label={`${experience.name} businesses`}
						checked={selected.includes(experience.key)}
						onchange={(checked) => toggle(experience.key, checked)}
					/>
				</li>
			{/each}
		</ul>

		{#if selected.length === 0}
			<p class="package-audience__hint">Choose at least one before the package can be published.</p>
		{/if}

		{#each gaps as gap (gap.experience.key)}
			<Banner type="warning">
				<p class="package-audience__gap">
					{gap.misfits.join(', ')}
					{gap.misfits.length === 1 ? 'does' : 'do'} not fit {gap.experience.name} businesses. Leave
					{gap.misfits.length === 1 ? 'it' : 'them'} out, or stop selling this package to {gap
						.experience.name} businesses.
				</p>
			</Banner>
		{/each}
	</div>
</SectionBlock>

<style lang="scss">
	.package-audience {
		display: grid;
		gap: var(--space-base);

		&__list {
			display: grid;
			gap: var(--space-slim);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__gap {
			margin: 0;
			line-height: var(--typography--lineHeight-base);
		}
	}
</style>
