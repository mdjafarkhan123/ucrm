<script lang="ts">
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import type { IncludedService, PackageService } from '$lib/jafar/packages';

	// Client onboarding A2 (plan §2.1): the package ticks services from Jafar's list. A ticked service starts
	// from the list's wording, which Jafar can change for this package; the wording is frozen with the
	// edition when published. The tick is what the setup wizard reads to show that service's stage.
	let {
		services,
		selected = $bindable(),
		errors,
		onEditList
	}: {
		services: PackageService[];
		selected: IncludedService[];
		errors: Record<string, string>;
		onEditList: () => void;
	} = $props();

	const known = $derived(new Set(services.map((service) => service.key)));
	// Archived services stay visible while this package still includes them, so Jafar can untick them.
	const shown = $derived(
		services.filter(
			(service) =>
				!service.archived_at || selected.some((entry) => entry.service_key === service.key)
		)
	);
	// Services written before the list existed, or since removed from it. Publishing refuses them.
	const unlisted = $derived(selected.filter((entry) => !known.has(entry.service_key)));

	function indexOf(key: string) {
		return selected.findIndex((entry) => entry.service_key === key);
	}

	function toggle(service: PackageService, checked: boolean) {
		if (!checked) {
			selected = selected.filter((entry) => entry.service_key !== service.key);
			return;
		}
		const order = services.map((candidate) => candidate.key);
		selected = [
			...selected,
			{ service_key: service.key, name: service.name, description: service.description }
		].sort((a, b) => order.indexOf(a.service_key) - order.indexOf(b.service_key));
	}

	function removeUnlisted(entry: IncludedService) {
		selected = selected.filter((candidate) => candidate !== entry);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="Included services"
	form
	id="package-services"
	hint="Work Uplift delivers in this package. Each ticked service adds its setup questions for the client. Do not promise rankings or 5-star reviews."
>
	{#snippet actions()}
		<Button size="small" variant="tertiary" onclick={onEditList}>Edit service list</Button>
	{/snippet}

	<div class="package-services">
		{#each unlisted as entry, position (position)}
			<div class="package-services__banner" role="status">
				<span class="package-services__banner-icon" aria-hidden="true">{@html alertIcon}</span>
				<p>
					“{entry.name || 'A service'}” is not on your service list. Remove it and tick a service
					from the list instead.
				</p>
				<Button size="small" variant="secondary" onclick={() => removeUnlisted(entry)}
					>Remove</Button
				>
			</div>
		{/each}

		{#if shown.length === 0}
			<p class="package-services__empty">
				Your service list is empty. Add the services Uplift sells with Edit service list.
			</p>
		{:else}
			<ul class="package-services__list">
				{#each shown as service (service.key)}
					{@const index = indexOf(service.key)}
					<li class="package-services__item">
						<div class="package-services__head">
							<Checkbox
								id={`package-service-${service.key}`}
								label={service.name}
								description={service.description}
								checked={index !== -1}
								onchange={(checked) => toggle(service, checked)}
							/>
							{#if service.archived_at}
								<Badge status="warning" size="small">Archived</Badge>
							{/if}
						</div>
						{#if index !== -1}
							<div class="package-services__wording">
								<Input
									id={`package-service-name-${service.key}`}
									size="small"
									label="Name customers see"
									maxlength={80}
									bind:value={selected[index].name}
									invalid={Boolean(errors[`included_services.${index}.name`])}
									errorMessage={errors[`included_services.${index}.name`]}
								/>
								<Textarea
									id={`package-service-description-${service.key}`}
									label="What the customer gets"
									rows={2}
									maxlength={300}
									bind:value={selected[index].description}
									invalid={Boolean(errors[`included_services.${index}.description`])}
									errorMessage={errors[`included_services.${index}.description`]}
								/>
							</div>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if errors.included_services}
			<p class="package-services__error" role="alert">{errors.included_services}</p>
		{/if}
	</div>
</SectionBlock>

<style lang="scss">
	.package-services {
		display: grid;
		gap: var(--space-base);

		&__list {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: grid;
			gap: var(--space-slim);
			padding: var(--space-slim) 0;
			border-top: var(--border-base) solid var(--color-border);

			&:first-child {
				border-top: 0;
			}
		}

		&__head {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__wording {
			display: grid;
			gap: var(--space-slim);
			margin-left: var(--space-large);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
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

	@media (max-width: 640px) {
		.package-services__wording {
			margin-left: 0;
		}
	}
</style>
