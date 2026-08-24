<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import ProductsAndServicesBlock from './ProductsAndServicesBlock.svelte';
	import {
		requestPricingKey,
		fetchRequestPricing,
		saveRequestPricing,
		type RequestPricingLineInput
	} from '$lib/quotes/api';

	// A request's side of the shared Products & Services block. Everything on screen lives in that block;
	// this only says which document is being priced and what a save means for it.
	let { requestId }: { requestId: string } = $props();

	const queryClient = useQueryClient();

	const pricingQuery = createQuery(() => ({
		queryKey: requestPricingKey(requestId),
		queryFn: () => fetchRequestPricing(requestId),
		enabled: Boolean(requestId)
	}));
	const saved = $derived(pricingQuery.data);

	async function save(expectedRevision: number, lines: RequestPricingLineInput[]) {
		try {
			await saveRequestPricing(requestId, expectedRevision, lines);
		} finally {
			// A stale save is refused, not applied, and either way the freshest rows are what should be on
			// screen next.
			await queryClient.invalidateQueries({ queryKey: requestPricingKey(requestId) });
		}
	}
</script>

<ProductsAndServicesBlock
	lines={saved?.lines ?? []}
	revision={saved?.revision ?? 0}
	editable={saved?.editable ?? false}
	currencyCode={saved?.currency_code ?? 'USD'}
	locale={saved?.locale ?? 'en-US'}
	loading={pricingQuery.isPending}
	loadFailed={pricingQuery.isError}
	attachTo={{ entityType: 'request', entityId: requestId }}
	editorTotalLabel="Request subtotal"
	saveLabel="Save pricing"
	lockedMessage="Pricing is locked because this request has already become a quote."
	onSave={save}
/>
