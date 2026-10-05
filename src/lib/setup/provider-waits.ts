// Client onboarding E2: outside waits (plan §5) — the steps Google, the phone carriers, a client's old phone
// company or their domain company take, each with its own badge, so a wait on them never makes Uplift look late
// or done. Industry reference: carrier registration and Google Business Profile verification report their own
// stage (submitted, in review, action needed, approved, failed); GuideCX and Rocketlane keep external
// dependencies on their own line, outside the delivery promise.
//
// Jafar's choices of 2026-10-05: four fixed waits, each offered only when the package includes its service;
// Jafar changes them by hand; the client sees a wait once Jafar has started it; only "You need to do something"
// emails the client. Mirrors supabase/migrations/20261031090000_setup_provider_waits.sql.

export const PROVIDER_WAITS = [
	'google_profile',
	'texting_approval',
	'number_transfer',
	'website_address'
] as const;
export type ProviderWaitKey = (typeof PROVIDER_WAITS)[number];

export const PROVIDER_WAIT_STATUSES = [
	'waiting_for_access',
	'submitted',
	'in_review',
	'action_needed',
	'approved',
	'unavailable'
] as const;
export type ProviderWaitStatus = (typeof PROVIDER_WAIT_STATUSES)[number];

export const PROVIDER_WAIT_NOTE_MAX = 1000;

/** The package service each wait belongs to. */
const WAIT_SERVICE: Record<ProviderWaitKey, string> = {
	google_profile: 'google_profile',
	texting_approval: 'calls_texting',
	number_transfer: 'calls_texting',
	website_address: 'website'
};

export const PROVIDER_WAIT_TITLE: Record<ProviderWaitKey, string> = {
	google_profile: 'Google profile',
	texting_approval: 'Texting approval',
	number_transfer: 'Number transfer',
	website_address: 'Website address'
};

/** Who the wait is with, as it reads mid-sentence to the client. */
const PROVIDER: Record<ProviderWaitKey, string> = {
	google_profile: 'Google',
	texting_approval: 'the phone carriers',
	number_transfer: 'your old phone company',
	website_address: 'your domain company'
};

/** The same, as Jafar reads it about a client. */
const OWNER_PROVIDER: Record<ProviderWaitKey, string> = {
	...PROVIDER,
	number_transfer: 'their old phone company',
	website_address: 'their domain company'
};

export type ProviderWait = {
	key: ProviderWaitKey;
	status: ProviderWaitStatus;
	note: string | null;
	updated_at: string;
};

function label(status: ProviderWaitStatus, provider: string, client: boolean) {
	switch (status) {
		case 'waiting_for_access':
			return client ? 'Waiting for your access' : 'Waiting for their access';
		case 'submitted':
			return `Sent to ${provider}`;
		case 'in_review':
			return `Being reviewed by ${provider}`;
		case 'action_needed':
			return client ? 'You need to do something' : 'They need to do something';
		case 'approved':
			return 'Approved';
		case 'unavailable':
			return 'Not possible';
	}
}

export const providerWaitLabel = (key: ProviderWaitKey, status: ProviderWaitStatus) =>
	label(status, PROVIDER[key], true);

export const providerWaitOwnerLabel = (key: ProviderWaitKey, status: ProviderWaitStatus) =>
	label(status, OWNER_PROVIDER[key], false);

/** While the provider has it, the client is told the time is not Uplift's (Jafar, 2026-10-05). */
export function providerWaitAside(key: ProviderWaitKey, status: ProviderWaitStatus) {
	if (status !== 'submitted' && status !== 'in_review') return null;
	const provider = PROVIDER[key];
	return `This is up to ${provider} — it isn't counted in Uplift's 7–10 days.`;
}

/** The badge colour, in StatusBadge's terms. */
export function providerWaitTone(
	status: ProviderWaitStatus
): 'informative' | 'warning' | 'success' | 'inactive' {
	if (status === 'action_needed') return 'warning';
	if (status === 'approved') return 'success';
	if (status === 'unavailable') return 'inactive';
	return 'informative';
}

/** Still waiting: not approved and not ruled out. */
export const providerWaitOpen = (status: ProviderWaitStatus) =>
	status !== 'approved' && status !== 'unavailable';

/** The waits a package offers, in order. */
export const providerWaitsFor = (serviceKeys: readonly string[]) =>
	PROVIDER_WAITS.filter((key) => serviceKeys.includes(WAIT_SERVICE[key]));

/** Rows as the database keeps them, minus anything that is no longer one of the waits. */
export function providerWaitsFromRows(
	rows: { wait_key: string; status: string; note: string | null; updated_at: string }[]
): ProviderWait[] {
	return PROVIDER_WAITS.flatMap((key) => {
		const row = rows.find((candidate) => candidate.wait_key === key);
		if (!row || !(PROVIDER_WAIT_STATUSES as readonly string[]).includes(row.status)) return [];
		return [
			{
				key,
				status: row.status as ProviderWaitStatus,
				note: row.note,
				updated_at: row.updated_at
			}
		];
	});
}
