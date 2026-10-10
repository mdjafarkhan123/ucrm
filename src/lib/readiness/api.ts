import { httpError } from '$lib/http-error';
import type { ReadinessAreaView } from '$lib/experience/readiness';

export type ReadinessSummary = { areas: ReadinessAreaView[] };

export async function fetchReadiness(): Promise<ReadinessSummary> {
	const response = await fetch('/api/readiness');
	if (!response.ok) throw httpError(response, 'What is switched on could not be loaded.');
	return response.json();
}

export const readinessKey = (userId: string | null) => ['readiness', userId] as const;
