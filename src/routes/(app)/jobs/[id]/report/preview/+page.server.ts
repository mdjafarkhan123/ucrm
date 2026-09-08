import { error as httpError } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import type { JobReportCustomerPreview } from '$lib/jobs/report-types';

// Preview as client, for the person looking at a job's work report. It reads the customer's document from the
// same database function that builds the customer's document, so what staff check here is what the client
// gets -- not a second rendering that agrees with it today and drifts tomorrow.
//
// It creates nothing. No recipient, no link, no token: looking at your own report is not sending it. This
// page breaks out of the app shell, so it does its own sign-in check rather than inheriting one.
export const load: PageServerLoad = async (event) => {
	await requireContractor(event);

	const { data, error } = await event.locals.supabase.rpc('job_report_customer_preview', {
		target_job_id: event.params.id
	});

	if (error) throw httpError(403, 'You do not have access to this job.');

	return { preview: data as unknown as JobReportCustomerPreview };
};
