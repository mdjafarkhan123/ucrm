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

	// Four ways in. Plain /invoices/new is the direct bill this screen has always written. Arriving with a
	// client — which is how "Create invoice" on a job gets here — first asks which of that client's work the
	// bill covers, then fills the same form with it. Arriving with specific visits (5b-2's visits-to-bill
	// card already did the choosing on the job page) skips that picker and seeds straight from them. Arriving
	// with one payment-schedule stage (5c-3) does the same, and the form it fills is read-only about money:
	// the stage's amount is the bill's amount, and the server is the one that prices it.
	const clientId = $derived(page.url.searchParams.get('client') ?? '');
	const jobId = $derived(page.url.searchParams.get('job'));
	const visitIds = $derived(
		(page.url.searchParams.get('visits') ?? '')
			.split(',')
			.map((id) => id.trim())
			.filter(Boolean)
	);
	const reminderIds = $derived(
		(page.url.searchParams.get('reminders') ?? '')
			.split(',')
			.map((id) => id.trim())
			.filter(Boolean)
	);
	const installmentId = $derived(page.url.searchParams.get('installment'));

	type Seed = {
		clientId: string;
		clientName: string;
		subject: string;
		propertyId: string | null;
		lines: RequestPricingLineInput[];
		sources: InvoiceSourceInput[];
		/** Set only when this bill is one payment-schedule stage. It takes a different save path entirely. */
		installmentId: string | null;
	};

	let seed = $state<Seed | null>(null);
	let picking = $state(false);
	let loadingSeed = $state(false);
	// The picker opens once per arrival; cancelling leaves rather than reopening it forever. Arriving with
	// visits already chosen skips it — there is nothing left to pick.
	$effect(() => {
		if (clientId && !seed && visitIds.length === 0 && reminderIds.length === 0 && !installmentId)
			picking = true;
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

	// Visits arrive pre-chosen (the job page's visits-to-bill card), so this seeds directly off the one job
	// once it loads rather than reopening a picker that has nothing left to ask. One copy of the job's priced
	// lines per visit, each stamped with that visit's own date — the 5b-2 shape approved on the roadmap.
	let attemptedVisitSeed = $state(false);
	$effect(() => {
		if (visitIds.length === 0 || seed || attemptedVisitSeed || !jobId) return;
		const job = originJobQuery.data;
		if (!job) return;
		attemptedVisitSeed = true;

		const jobLines = pricedLines(job.lines);
		if (jobLines.length === 0) {
			toast.error('That job has no priced lines yet, so there is nothing to bill.');
			void goto(resolve('/(app)/jobs/[id]', { id: jobId }));
			return;
		}

		const visitDateById = new Map(job.visits.map((visit) => [visit.id, visit.visit_date]));
		seed = {
			clientId,
			clientName,
			subject: job.job.title,
			propertyId: job.job.property?.id ?? null,
			lines: visitIds.flatMap((visitId) =>
				jobLines.map((line) => ({ ...line, service_date: visitDateById.get(visitId) ?? null }))
			),
			sources: visitIds.map((visitId) => ({ kind: 'visit', job_id: jobId, visit_id: visitId })),
			installmentId: null
		};
	});

	// Periods arrive pre-chosen (the job page's periods-to-bill card), same shape as visits: one copy of the
	// job's priced lines per selected period, each stamped with that period's own end date (5b-3).
	let attemptedReminderSeed = $state(false);
	$effect(() => {
		if (reminderIds.length === 0 || seed || attemptedReminderSeed || !jobId) return;
		const job = originJobQuery.data;
		if (!job) return;
		attemptedReminderSeed = true;

		const jobLines = pricedLines(job.lines);
		if (jobLines.length === 0) {
			toast.error('That job has no priced lines yet, so there is nothing to bill.');
			void goto(resolve('/(app)/jobs/[id]', { id: jobId }));
			return;
		}

		const reminderDueById = new Map(
			job.reminders.map((reminder) => [reminder.id, reminder.due_on])
		);
		seed = {
			clientId,
			clientName,
			subject: job.job.title,
			propertyId: job.job.property?.id ?? null,
			lines: reminderIds.flatMap((reminderId) =>
				jobLines.map((line) => ({ ...line, service_date: reminderDueById.get(reminderId) ?? null }))
			),
			sources: reminderIds.map((reminderId) => ({
				kind: 'reminder_period',
				job_id: jobId,
				reminder_id: reminderId
			})),
			installmentId: null
		};
	});

	// One payment-schedule stage arrives pre-chosen (the job page's billing card), so the only thing left is
	// to show what it will bill before the contractor commits. The stage's amount is spread across the job's
	// priced lines here purely as a preview — `create_installment_invoice` prices the stage and splits it
	// again on the server when this saves, so nothing typed in the browser can move the money. This mirrors
	// `private.progress_invoice_lines` exactly: share by each line's total, largest remainder first, ties by
	// position; an all-zero job splits evenly by line count instead.
	function stageLines(
		jobLines: RequestPricingLineInput[],
		lineTotals: number[],
		stageAmountMinor: number
	): RequestPricingLineInput[] {
		const baseTotal = lineTotals.reduce((sum, total) => sum + total, 0);
		const weights = lineTotals.map((total) => (baseTotal > 0 ? total : 1));
		const weightTotal = baseTotal > 0 ? baseTotal : jobLines.length;

		const shares = weights.map((weight) => {
			const exact = (stageAmountMinor * weight) / weightTotal;
			const base = Math.floor(exact);
			return { base, fraction: exact - base };
		});
		let residual = stageAmountMinor - shares.reduce((sum, share) => sum + share.base, 0);
		const order = shares
			.map((share, index) => ({ index, fraction: share.fraction }))
			.sort((a, b) => b.fraction - a.fraction || a.index - b.index);
		for (const entry of order) {
			if (residual <= 0) break;
			shares[entry.index].base += 1;
			residual -= 1;
		}

		// Quantity is forced to 1 and the unit label dropped: the figure on the line is the share of the
		// stage this line carries, not a rate times an amount of work, and "1 hour" beside it would lie.
		return jobLines.map((line, index) => ({
			...line,
			unit_label: null,
			quantity: 1,
			unit_price_minor: shares[index].base,
			unit_cost_minor: 0,
			image_attachment_id: null
		}));
	}

	let attemptedInstallmentSeed = $state(false);
	$effect(() => {
		if (!installmentId || seed || attemptedInstallmentSeed || !jobId) return;
		const job = originJobQuery.data;
		if (!job) return;
		attemptedInstallmentSeed = true;

		const backToJob = (message: string) => {
			toast.error(message);
			void goto(resolve('/(app)/jobs/[id]', { id: jobId }));
		};

		const stage = job.schedule?.stages.find((entry) => entry.installment_id === installmentId);
		if (!stage) {
			backToJob('That payment stage is no longer on this job.');
			return;
		}
		if (stage.status !== 'remaining') {
			backToJob('That payment stage has already been billed.');
			return;
		}
		if (stage.amount_minor === null) {
			backToJob('That payment stage has no amount yet, so there is nothing to bill.');
			return;
		}

		const priced = job.lines.filter((line) => line.line_kind === 'priced');
		const jobLines = pricedLines(job.lines);
		if (jobLines.length === 0) {
			backToJob('That job has no priced lines yet, so there is nothing to bill.');
			return;
		}

		seed = {
			clientId,
			clientName,
			// The stage names the bill — "Deposit", "On completion" — under the job it belongs to, which is
			// what the contractor and the client both need to see on the invoice.
			subject: `${job.job.title} — ${stage.description}`,
			propertyId: job.job.property?.id ?? null,
			lines: stageLines(
				jobLines,
				priced.map((line) => line.line_total_minor ?? 0),
				stage.amount_minor
			),
			// The claim the server will write for this bill. It carries the job so the form knows what it is
			// billing; the stage id travels beside it, because that is what the command takes.
			sources: [{ kind: 'installment', job_id: jobId }],
			installmentId
		};
	});

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
				sources: chosen.map((item) => ({ kind: 'job_total', job_id: item.job_id })),
				installmentId: null
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
