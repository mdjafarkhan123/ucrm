<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PaperworkListCard from '$lib/components/communications/paperwork/PaperworkListCard.svelte';
	import PaperworkSideCards from '$lib/components/communications/paperwork/PaperworkSideCards.svelte';
	import { fetchPaperworkList, paperworkKeys } from '$lib/communications/number-paperwork';
	import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
	import filePlusIcon from '@tabler/icons/outline/file-plus.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';

	// Number paperwork (Stage 10 Part 3, `concept.pen` board `A0URqF`): the sets a business has sent or started,
	// one per country and kind of number.
	const query = createQuery(() => ({
		queryKey: paperworkKeys.list(),
		queryFn: () => fetchPaperworkList()
	}));
</script>

<svelte:head><title>Number paperwork · Contractor CRM</title></svelte:head>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="open">
	<div class="number-paperwork">
		<Breadcrumbs
			items={[
				{ label: 'Settings', href: resolve('/(app)/settings') },
				{
					label: 'Phone & SMS',
					href: resolve('/(app)/settings/communications/sms'),
					icon: messageIcon
				},
				{ label: 'Number paperwork', icon: fileCheckIcon }
			]}
		/>
		<PageHeader
			icon={fileCheckIcon}
			tone="conversation"
			title="Number paperwork"
			description="Some countries ask who you are before you can buy a texting number there. Each set covers one country and kind of number."
		>
			{#snippet actions()}
				<Button href={resolve('/(app)/settings/communications/sms/paperwork/new')}>
					<span aria-hidden="true">{@html filePlusIcon}</span>
					New paperwork
				</Button>
			{/snippet}
		</PageHeader>

		<div class="number-paperwork__body">
			<PaperworkListCard
				sets={query.data?.paperwork ?? []}
				loading={query.isPending}
				failed={query.isError}
				retry={() => query.refetch()}
			/>
			<PaperworkSideCards reused={query.data?.reused ?? null} />
		</div>
	</div>
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.number-paperwork {
		&__body {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 360px;
			align-items: start;
			gap: var(--space-large);
		}
	}

	@media (max-width: 1023px) {
		.number-paperwork__body {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
