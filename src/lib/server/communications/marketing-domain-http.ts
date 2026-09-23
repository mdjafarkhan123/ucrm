import { json } from '@sveltejs/kit';
import { CloudflareDnsError } from './cloudflare-dns';
import { EmailDomainActivationError } from './dns-reconcile';
import { SesError } from './ses-env';

const noStore = { 'Cache-Control': 'no-store' };

/**
 * One error contract shared by the two owner Marketing sending-identity routes.
 *
 * A non-retryable decision (an occupied name, a domain claimed by another organization) is a 409 the owner
 * resolves by hand. An ambiguous provider outcome -- a timeout, a network failure, or a 5xx from Cloudflare or
 * SES -- is a 502 that is always safe to re-run, because the reconciler is a desired-state saga that wrote
 * nothing it cannot re-derive from current provider state. Provider messages never reach the response.
 */
export function marketingDomainErrorResponse(error: unknown, action: 'activate' | 'recheck') {
	if (error instanceof EmailDomainActivationError && !error.retryable) {
		return json({ error: error.message, code: error.code }, { status: 409, headers: noStore });
	}
	// SES is a reserved integration the app boots without, so "not configured yet" is a service state rather
	// than a failure the owner can retry into success.
	if (error instanceof SesError && error.code === 'ses_not_configured') {
		return json(
			{ error: 'Amazon SES is not configured yet.', code: error.code },
			{ status: 503, headers: noStore }
		);
	}

	const providerUnknown =
		error instanceof EmailDomainActivationError ||
		(error instanceof CloudflareDnsError && (error.status === null || error.status >= 500)) ||
		(error instanceof SesError && (error.status === null || error.status >= 500));
	if (providerUnknown) {
		console.error(
			`Could not ${action} the Marketing sending domain (provider outcome unknown).`,
			error
		);
		return json(
			{ error: 'A provider did not confirm the change. Check the domain and try again.' },
			{ status: 502, headers: noStore }
		);
	}
	if (error instanceof CloudflareDnsError) {
		console.error(`Could not ${action} the Marketing sending domain (Cloudflare rejected).`, error);
		return json(
			{ error: 'Cloudflare rejected a DNS change during Marketing activation.' },
			{ status: 502, headers: noStore }
		);
	}
	if (error instanceof SesError) {
		console.error(`Could not ${action} the Marketing sending domain (SES rejected).`, error);
		return json(
			{ error: 'Amazon SES could not complete the Marketing sending identity.' },
			{ status: 502, headers: noStore }
		);
	}

	console.error(`Could not ${action} the Marketing sending domain.`, error);
	return json(
		{
			error:
				action === 'activate'
					? 'The Marketing sending domain could not be activated.'
					: 'The Marketing sending domain could not be rechecked.'
		},
		{ status: 500, headers: noStore }
	);
}
