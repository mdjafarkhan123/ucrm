import type { PageServerLoad } from './$types';

// The reset link a teammate opens from their email (D1, ADR 0008). The link's secret never leaves this page:
// no caching, no referrer, no indexing. Whether it still works is learned on submit, so opening the page
// cannot be used to test links.
export const load: PageServerLoad = ({ setHeaders }) => {
	setHeaders({
		'cache-control': 'no-store',
		'referrer-policy': 'no-referrer',
		'x-robots-tag': 'noindex, nofollow, noarchive'
	});
};
