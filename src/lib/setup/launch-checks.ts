// Client onboarding E5: launch checks (plan §6). Before asking for launch approval, Jafar tests each line the
// client's package needs and ticks it, or marks it Doesn't apply with a reason. A line that depends on an outside
// wait still open shows Waiting on that provider and is never ticked; Ask waits until no line is unchecked. When
// Jafar asks, the list is kept with the request and the approver sees it. Industry reference: milestone gating in
// Rocketlane and GuideCX, and agencies' go-live QA checklists with a "doesn't apply" option.
// Mirrors supabase/migrations/20261103090000_setup_launch_checks.sql.

import {
	PROVIDER_WAIT_TITLE,
	providerWaitLabel,
	type ProviderWaitKey,
	type ProviderWaitStatus
} from './provider-waits';

/** The lines, in order: the package service each needs (null: everyone's) and the waits it is tested after. */
export const LAUNCH_CHECKS = [
	{ key: 'web_address', service: 'website', waits: ['website_address'] },
	{ key: 'phone_look', service: 'website', waits: [] },
	{ key: 'form_leads', service: 'website', waits: [] },
	{ key: 'email_delivery', service: null, waits: [] },
	{ key: 'calls_texts', service: 'calls_texting', waits: ['texting_approval', 'number_transfer'] },
	{ key: 'stop_help', service: 'calls_texting', waits: ['texting_approval'] },
	{ key: 'imports', service: null, waits: [] },
	{ key: 'account_ownership', service: null, waits: [] },
	{ key: 'everything_else', service: null, waits: [] }
] as const satisfies readonly {
	key: string;
	service: string | null;
	waits: readonly ProviderWaitKey[];
}[];

export type LaunchCheckKey = (typeof LAUNCH_CHECKS)[number]['key'];
export const LAUNCH_CHECK_KEYS = LAUNCH_CHECKS.map((check) => check.key) as [
	LaunchCheckKey,
	...LaunchCheckKey[]
];

export const LAUNCH_CHECK_REASON_MAX = 300;

/** What the line says was tested, as both Jafar and the approver read it. */
export const LAUNCH_CHECK_TITLE: Record<LaunchCheckKey, string> = {
	web_address: 'The web address opens the site securely (padlock showing)',
	phone_look: 'The website looks right on a phone',
	form_leads: 'A test form on the website arrives as a new lead in the CRM',
	email_delivery: 'Emails from the system arrive',
	calls_texts: 'Calls, the missed-call text and text replies work',
	stop_help: 'STOP and HELP texts get the right answer',
	imports: 'Imported clients and records add up',
	account_ownership: 'The business owns its accounts and logins',
	everything_else: 'Everything else in the package works'
};

/** How Jafar tests it. */
export const LAUNCH_CHECK_HINT: Record<LaunchCheckKey, string> = {
	web_address: 'Open the address in a private window; it loads without a warning.',
	phone_look: 'Open each page on a phone; nothing is cut off or overlapping.',
	form_leads: 'Send each form once and find the lead in their CRM.',
	email_delivery: 'Send a test email from their account and see that it arrives, not in spam.',
	calls_texts: 'Call the number, leave it unanswered, and reply to the text that comes back.',
	stop_help: 'Text STOP and HELP to their number.',
	imports: 'Compare the counts in the CRM with the files they sent.',
	account_ownership: 'Their domain, Google profile and other accounts are in their name.',
	everything_else: 'Go through their package and try each feature once.'
};

export type LaunchCheckState = 'checked' | 'not_applicable' | 'waiting' | 'unchecked';

/** One line as the database returns it. Jafar's read adds who ticked it. */
export type LaunchCheckLine = {
	key: LaunchCheckKey;
	state: LaunchCheckState;
	reason: string | null;
	checked_at: string | null;
	checked_by_email?: string | null;
	waiting_on: ProviderWaitKey[];
};

/** The checklist: every line, and every outside wait still open. */
export type LaunchChecklist = {
	lines: LaunchCheckLine[];
	waits: { key: ProviderWaitKey; status: ProviderWaitStatus }[];
};

/** Jafar's read: the newest released version's list, and whether a request was made on it. */
export type OwnerLaunchChecklist = LaunchChecklist & { version: number; asked: boolean };

/** Lines still to tick or mark; Ask waits for none. */
export const uncheckedLaunchLines = (checklist: LaunchChecklist) =>
	checklist.lines.filter((line) => line.state === 'unchecked');

/** Who a waiting line is on, mid-sentence: "Waiting on the phone carriers". */
const WAIT_PROVIDER: Record<ProviderWaitKey, string> = {
	google_profile: 'Google',
	texting_approval: 'the phone carriers',
	number_transfer: 'the old phone company',
	website_address: 'the domain company'
};

export function launchCheckWaitingLabel(waits: readonly ProviderWaitKey[]) {
	const names = [...new Set(waits.map((key) => WAIT_PROVIDER[key]))];
	return `Waiting on ${names.join(' and ')}`;
}

/** An open wait as the approver reads it: "Texting approval — Being reviewed by the phone carriers". */
export const launchWaitLine = (wait: { key: ProviderWaitKey; status: ProviderWaitStatus }) =>
	`${PROVIDER_WAIT_TITLE[wait.key]} — ${providerWaitLabel(wait.key, wait.status)}`;

/** The kept list, or null on a request made before E5 or a value that is not one. */
export function launchChecklistFrom(value: unknown): LaunchChecklist | null {
	if (!value || typeof value !== 'object') return null;
	const { lines, waits } = value as Partial<LaunchChecklist>;
	if (!Array.isArray(lines) || !Array.isArray(waits)) return null;
	return {
		lines: lines.filter((line) => line && LAUNCH_CHECK_KEYS.includes(line.key)),
		waits: waits.filter((wait) => wait && wait.key in PROVIDER_WAIT_TITLE)
	};
}
