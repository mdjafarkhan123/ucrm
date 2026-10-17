<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import LifecycleTrack, { type TrackStep } from './LifecycleTrack.svelte';
	import {
		buildRecordTrack,
		fetchRecordChain,
		recordChainKey,
		type RecordKind
	} from '$lib/work/record-chain';

	// The progress strip on a request, quote, job or invoice page: where this record sits on the line
	// Request > Quote > Job > Invoice > Paid. The page says which record it is; the database follows the links.
	// Until the answer arrives the five names are already there, so nothing jumps when it lands.

	let {
		kind,
		id,
		clientName,
		clientIsCompany = false
	}: {
		kind: RecordKind;
		id: string;
		clientName?: string;
		clientIsCompany?: boolean;
	} = $props();

	const chain = createQuery(() => ({
		queryKey: recordChainKey(kind, id),
		queryFn: () => fetchRecordChain(kind, id),
		staleTime: 30_000
	}));

	const waiting: TrackStep[] = ['Request', 'Quote', 'Job', 'Invoice', 'Paid'].map((label) => ({
		label,
		sub: ' ',
		state: 'todo'
	}));

	const steps = $derived(
		chain.data
			? buildRecordTrack(chain.data, {
					kind,
					clientName,
					clientIsCompany,
					links: {
						request: (target) => resolve('/(app)/requests/[id=uuid]', { id: target }),
						quote: (target) => resolve('/(app)/quotes/[id=uuid]', { id: target }),
						job: (target) => resolve('/(app)/jobs/[id=uuid]', { id: target }),
						invoice: (target) => resolve('/(app)/invoices/[id=uuid]', { id: target })
					}
				})
			: waiting
	);
</script>

{#if !chain.isError}
	<LifecycleTrack {steps} label="Progress from request to paid" />
{/if}
