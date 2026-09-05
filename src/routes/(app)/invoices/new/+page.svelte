<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import InvoiceForm from '$lib/components/invoices/InvoiceForm.svelte';
	import { fetchInvoiceOverview, invoiceCountsKey } from '$lib/invoices/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	// The organization's money format, so the line editor and the total card write figures the same way the
	// Invoices list does. Coming from that list it is already cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: invoiceCountsKey,
		queryFn: fetchInvoiceOverview,
		staleTime: 60_000
	}));

	const toast = getToastManager();

	function handleSaved(invoice: { id: string; number: number }) {
		// A new invoice lands on its own detail page. The toast rides along through the navigation to confirm it.
		toast.success(`Invoice #${invoice.number} created`);
		void goto(resolve('/(app)/invoices/[id]', { id: invoice.id }));
	}
</script>

<svelte:head><title>New invoice · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<InvoiceForm
		currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
		locale={overviewQuery.data?.locale ?? 'en-US'}
		onSaved={handleSaved}
		onCancel={() => goto(resolve('/(app)/invoices'))}
	/>
</PageContainer>
