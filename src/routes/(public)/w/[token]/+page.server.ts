import type { PageServerLoad } from './$types';
import {
	getJobReportAccessResolverClient,
	jobReportAccessTokenHash
} from '$lib/server/jobs/report-access-links';
import type { CustomerJobReportDocument } from '$lib/jobs/report-types';

// The customer's copy of a work report. This is the only place a stranger can reach a job's report, and it
// reaches it the long way round: the token from the URL is hashed here, the hash goes to the one function the
// service role may call, and that function decides what a customer is allowed to see.
//
// Every way of failing looks the same: an unknown token, a revoked one, an expired one, or a report that no
// longer has content all come back as `document: null`, so the page cannot be used to find out whether a job
// or an organization exists.
//
// Loading the page records nothing. Mail scanners and chat link previews fetch URLs before any person sees
// them; the view is recorded by the browser once the document is actually drawn.
export const load: PageServerLoad = async ({ params, setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});

	const tokenHash = jobReportAccessTokenHash(params.token);
	if (!tokenHash) return { document: null };

	const { data, error } = await getJobReportAccessResolverClient().rpc(
		'resolve_job_report_access_link',
		{ supplied_token_hash: tokenHash }
	);

	// Deliberately not logged with the token or the reason. A failure here is either a broken link or
	// somebody guessing, and neither should write a customer's URL into a log file.
	if (error || !data) return { document: null };

	return { document: data as unknown as CustomerJobReportDocument };
};
