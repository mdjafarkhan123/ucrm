import type { RecordLifecycleStep } from './types';

/** Show only what the caller knows. Opening a job never proves a quote/request existed or was finished. */
export function recordLifecycle(
	current: RecordLifecycleStep['key'],
	status: string,
	known: Partial<
		Record<RecordLifecycleStep['key'], Omit<RecordLifecycleStep, 'key' | 'current'>>
	> = {}
): RecordLifecycleStep[] {
	return (['request', 'quote', 'job', 'invoice', 'paid'] as const).map((key) => ({
		key,
		label: { request: 'Request', quote: 'Quote', job: 'Job', invoice: 'Invoice', paid: 'Paid' }[
			key
		],
		...known[key],
		...(key === current ? { current: true, detail: status } : {})
	}));
}
