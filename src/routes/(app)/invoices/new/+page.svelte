<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import InvoiceForm from '$lib/components/invoices/InvoiceForm.svelte';
	import SelectWorkDialog from '$lib/components/invoices/SelectWorkDialog.svelte';
	import {
		fetchInvoiceOverview,
		invoiceCountsKey,
		type BillableWorkItem,
		type InvoiceSourceInput
	} from '$lib/invoices/api';
	import { fetchJob, jobDetailKey } from '$lib/jobs/api';
	import type { RequestPricingLineInput } from '$lib/quotes/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	// The money format, so the line editor and the total card write figures the same way the Invoices list
	// does. Coming from that list it is already cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: invoiceCountsKey,
		queryFn: fetchInvoiceOverview,
		staleTime: 60_000
	}));

	const toast = getToastManager();

	// Two ways in. Plain /invoices/new is the direct bill this screen has always written. Arriving with a
	// client — which is how "Create invoice" on a job gets here — first asks which of that client's work the
	// bill covers, then fills the same form with it.
	const clientId = $derived(page.url.searchParams.get('client') ?? '');
	const jobId = $derived(page.url.searchParams.get('job'));

	type Seed = {
		clientId: string;
		clientName: string;
		subject: string;
		propertyId: string | null;
		lines: RequestPricingLineInput[];
		sources: InvoiceSourceInput[];
	};

	let seed = $state<Seed | null>(null);
	let picking = $state(false);
	let loadingSeed = $state(false);
	// The picker opens once per arrival; cancelling leaves rather than reopening it forever.
	$effect(() => {
		if (clientId && !seed) picking = true;
	});

	// The client's name for the picker's title. It rides along on the job the contractor came from, so no
	// extra client fetch is needed for the common path.
	const originJobQuery = createQuery(() => ({
		queryKey: jobDetailKey(jobId ?? ''),
		queryFn: () => fetchJob(jobId!),
		enabled: Boolean(jobId),
		staleTime: 30_000
	}));
	const clientName = $derived(
		originJobQuery.data?.job.client?.display_name ??
			originJobQuery.data?.job.client?.company_name ??
			'this client'
	);

	// A job's priced lines become the invoice's opening lines, editable like any other. Headings and notes
	// stay behind: an invoice line bills work, and the contract says only priced work is billable.
	function pricedLines(lines: Awaited<ReturnType<typeof fetchJob>>['lines']) {
		return lines
			.filter((line) => line.line_kind === 'priced')
			.map((line) => ({
				name: line.name,
				category: (line.category ?? 'service') as RequestPricingLineInput['category'],
				is_labor: line.is_labor,
				catalog_item_id: line.source_catalog_item_id,
				description: line.description,
				unit_label: line.unit_label,
				quantity: line.quantity ?? 1,
				unit_price_minor: line.unit_price_minor ?? 0,
				unit_cost_minor: line.unit_cost_minor ?? 0,
				is_taxable: line.is_taxable,
				image_attachment_id: line.image_attachment_id
			})) satisfies RequestPricingLineInput[];
	}

	async function continueWith(chosen: BillableWorkItem[]) {
		if (chosen.length === 0 || loadingSeed) return;
		loadingSeed = true;
		try {
			// Bounded by the selection the picker allowed, so this is a handful of requests, not a page of them.
			const jobs = await Promise.all(chosen.map((item) => fetchJob(item.job_id)));
			const lines = jobs.flatMap((detail) => pricedLines(detail.lines));

			if (lines.length === 0) {
				toast.error('That work has no priced lines yet, so there is nothing to bill.');
				return;
			}

			seed = {
				clientId,
				clientName,
				// One job bills under its own name, the way Jobber does it; several share the neutral default.
				subject: jobs.length === 1 ? jobs[0].job.title : 'For services rendered',
				propertyId: jobs[0].job.property?.id ?? null,
				lines,
				sources: chosen.map((item) => ({ kind: 'job_total', job_id: item.job_id }))
			};
			picking = false;
		} catch {
			toast.error('That work could not be loaded. Try again.');
		} finally {
			loadingSeed = false;
		}
	}

	function leave() {
		picking = false;
		void goto(jobId ? resolve('/(app)/jobs/[id]', { id: jobId }) : resolve('/(app)/invoices'));
	}

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
		{seed}
		onSaved={handleSaved}
		onCancel={leave}
	/>
</PageContainer>

{#if clientId}
	<SelectWorkDialog
		open={picking}
		{clientId}
		{clientName}
		initialJobId={jobId}
		currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
		locale={overviewQuery.data?.locale ?? 'en-US'}
		onCancel={leave}
		onContinue={continueWith}
	/>
{/if}
