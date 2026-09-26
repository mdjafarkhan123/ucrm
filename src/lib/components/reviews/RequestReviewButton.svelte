<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ReviewRequestForm from './ReviewRequestForm.svelte';
	import {
		fetchReviewRequestContext,
		reviewRequestContextKey,
		type ReviewRequestTarget
	} from '$lib/reviews/requests';

	// Google review campaign Part 3: "Request a review" on a job or a client. The panel's details stay unloaded
	// until the button is hovered, prefetch then, and are cached so reopening is instant.
	let {
		target,
		size = 'small',
		variant = 'secondary'
	}: {
		target: ReviewRequestTarget;
		size?: 'small' | 'base';
		variant?: 'primary' | 'secondary' | 'tertiary';
	} = $props();

	const queryClient = useQueryClient();
	let open = $state(false);
	let armed = $state(false);

	const contextQuery = createQuery(() => ({
		queryKey: reviewRequestContextKey(target),
		queryFn: () => fetchReviewRequestContext(target),
		enabled: armed,
		staleTime: 30_000
	}));

	function warm() {
		armed = true;
		void queryClient.prefetchQuery({
			queryKey: reviewRequestContextKey(target),
			queryFn: () => fetchReviewRequestContext(target),
			staleTime: 30_000
		});
	}

	function show() {
		armed = true;
		open = true;
	}
</script>

<Button {size} {variant} onhover={warm} onclick={show}>Request a review</Button>

{#if open}
	<Dialog {open} title="Request a review" onClose={() => (open = false)}>
		{#if contextQuery.isPending}
			<LoadingSkeleton variant="card" label="Loading review request" />
		{:else if contextQuery.isError}
			<ErrorState description={contextQuery.error.message} retry={() => contextQuery.refetch()} />
		{:else if contextQuery.data}
			<ReviewRequestForm context={contextQuery.data} onDone={() => (open = false)} />
		{/if}
	</Dialog>
{/if}
