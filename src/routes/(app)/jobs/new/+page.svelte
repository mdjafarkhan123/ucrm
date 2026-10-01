<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createQuery } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import JobForm from '$lib/components/jobs/JobForm.svelte';
	import { fetchJobOverview, jobCountsKey } from '$lib/jobs/api';
	import { takeJobCreateSeed, type JobCreateSeed } from '$lib/jobs/createDraft';
	import { fetchRequest, requestDetailKey, type RequestDetail } from '$lib/requests/api';
	import { fetchRequestPricing, requestPricingKey, type RequestPricing } from '$lib/quotes/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	// A draft may have been staged by Schedule's compact create form when the person pressed More Options.
	// It is read once, here on the way in, so this page opens filled; a later plain visit reads nothing and
	// opens blank.
	const staged = takeJobCreateSeed();

	// "Convert to job" on a request lands here with the request in the address, so a reload keeps the
	// conversion instead of quietly turning it into an unrelated blank job. Coming from the request page
	// both reads below are already cached, so the form opens filled without waiting.
	const requestId = page.url.searchParams.get('request') ?? '';
	const convertingRequest = /^[0-9a-f-]{36}$/i.test(requestId);

	const requestQuery = createQuery(() => ({
		queryKey: requestDetailKey(requestId),
		queryFn: () => fetchRequest(requestId),
		enabled: convertingRequest,
		staleTime: 15_000
	}));
	// Someone who may not see request pricing still converts the request; the job simply opens with no
	// lines carried over.
	const pricingQuery = createQuery(() => ({
		queryKey: requestPricingKey(requestId),
		queryFn: () => fetchRequestPricing(requestId),
		enabled: convertingRequest,
		staleTime: 15_000,
		retry: false
	}));

	// The same live-work allowlist the database enforces for turning a request into a quote or a job.
	const CONVERTIBLE_STATUSES = ['new', 'unscheduled', 'assessment_completed'];
	const sourceRequest = $derived(requestQuery.data);
	const requestReady = $derived(
		!convertingRequest || (requestQuery.isSuccess && !pricingQuery.isPending)
	);
	const requestClosed = $derived(
		Boolean(sourceRequest && !CONVERTIBLE_STATUSES.includes(sourceRequest.stored_status))
	);

	function requestSeed(request: RequestDetail, pricing: RequestPricing | undefined): JobCreateSeed {
		return {
			// The picker's row shape, built from what the request already carries. The job stays at the
			// request's own property, so no other property is offered.
			client: request.client
				? {
						id: request.client.id,
						display_name: request.client.display_name,
						company_name: request.client.company_name,
						client_type: request.client.client_type,
						lifecycle_status: '',
						lead_source: null,
						archived_at: null,
						updated_at: request.updated_at,
						primary_property: request.property
							? {
									id: request.property.id,
									label: request.property.label ?? '',
									address_line1: request.property.address_line1,
									city: request.property.city,
									state_region: request.property.state_region,
									postal_code: request.property.postal_code
								}
							: null,
						additional_property_count: 0,
						email: request.email,
						phone: request.phone,
						tags: []
					}
				: null,
			property_id: request.property_id,
			title: request.title,
			first_visit: null,
			request: { id: request.id, title: request.title, lines: pricing?.lines ?? [] }
		};
	}

	// The form opens once and then keeps what it opened with. Saving refreshes the request, which by then
	// reads Converted; without this latch the page would swap the form for "already converted" in the moment
	// before it moves on to the new job.
	let seed = $state.raw<JobCreateSeed | null>(staged);
	let formOpen = $state(!convertingRequest);
	$effect(() => {
		if (formOpen || !requestReady || !sourceRequest || requestClosed) return;
		seed = requestSeed(sourceRequest, pricingQuery.data);
		formOpen = true;
	});

	// The organization's money format, so the line editor and the Job total card write figures the same way
	// the Jobs list does. Coming from that list it is already cached, so nothing waits on it.
	const overviewQuery = createQuery(() => ({
		queryKey: jobCountsKey,
		queryFn: fetchJobOverview,
		staleTime: 60_000
	}));

	const toast = getToastManager();

	function handleSaved(job: { id: string; number: number; fromRequest: boolean }) {
		// A new job lands on its own detail page, the way a saved quote does. The toast rides along through the
		// navigation to confirm it.
		toast.success(
			job.fromRequest ? `Request converted to Job #${job.number}` : `Job #${job.number} created`
		);
		void goto(resolve('/(app)/jobs/[id=uuid]', { id: job.id }));
	}

	function handleCancel() {
		if (sourceRequest) {
			void goto(resolve('/(app)/requests/[id=uuid]', { id: sourceRequest.id }));
		} else {
			void goto(resolve('/(app)/jobs'));
		}
	}
</script>

<svelte:head><title>New job · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	{#if formOpen}
		<JobForm
			{seed}
			currencyCode={overviewQuery.data?.currency_code ?? 'USD'}
			locale={overviewQuery.data?.locale ?? 'en-US'}
			onSaved={handleSaved}
			onCancel={handleCancel}
		/>
	{:else if requestQuery.isError}
		<ErrorState description="That request could not be loaded. Go back to it and try again." />
	{:else if !requestReady}
		<LoadingSkeleton variant="card" label="Loading the request" />
	{:else if sourceRequest && requestClosed}
		<ErrorState
			title="This request cannot become a job"
			description={sourceRequest.stored_status === 'converted'
				? 'It has already been converted.'
				: 'Only a request that is still open can be turned into a job.'}
		>
			{#snippet action()}
				<Button
					variant="secondary"
					href={resolve('/(app)/requests/[id=uuid]', { id: sourceRequest.id })}
				>
					Back to the request
				</Button>
			{/snippet}
		</ErrorState>
	{/if}
</PageContainer>
