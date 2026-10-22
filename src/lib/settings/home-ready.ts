import type { SettingsHome, SettingsHomeSummary } from '$lib/settings/api';

// "Ready for customers": the things a customer eventually runs into, each a plain yes/no the app can check.
// One the member may not open, or whose figure has not loaded, is left out of the count rather than guessed.
export type ReadyKey =
	| 'profile'
	| 'hours'
	| 'logo'
	| 'tax'
	| 'payments'
	| 'texting'
	| 'email'
	| 'products'
	| 'team'
	| 'forms'
	| 'alerts'
	| 'reviews';

export type ReadyItem = { key: ReadyKey; title: string; done: boolean };

export type ReadyList = { done: number; total: number; items: ReadyItem[] };

export function settingsReady(
	home: Pick<SettingsHome, 'permissions' | 'readiness'>,
	summary: Pick<SettingsHomeSummary, 'signals'> | undefined
): ReadyList {
	const items: ReadyItem[] = [];
	const add = (key: ReadyKey, title: string, done: boolean | null | undefined) => {
		if (done === null || done === undefined) return;
		items.push({ key, title, done });
	};
	const signals = summary?.signals;
	const sms = home.readiness.sms_registration?.readiness_state ?? null;

	add('profile', 'Finish your business profile', home.readiness.business_profile.complete);
	add('hours', 'Set your business hours', home.readiness.business_hours_set);
	add('logo', 'Add your logo', signals?.logo);
	add('tax', 'Choose a default tax rate', signals?.tax_default);
	add('payments', 'Connect online payments', signals?.payments_connected);
	add(
		'texting',
		sms === 'under_review' ? 'Texting is in review' : 'Finish texting setup',
		sms === null || sms === 'not_included' ? null : sms === 'ready'
	);
	add('email', 'Set up your email address', signals?.email_verified);
	add(
		'products',
		'Add products and services',
		signals ? (signals.products === null ? null : signals.products > 0) : null
	);
	add(
		'team',
		'Invite your team',
		signals ? (signals.team_members === null ? null : signals.team_members > 1) : null
	);
	add(
		'forms',
		'Turn on a request form',
		signals ? (signals.request_forms === null ? null : signals.request_forms > 0) : null
	);
	add(
		'alerts',
		'Choose who hears about new customers',
		home.permissions.communications_manage ? !home.readiness.inquiry_alerts_owner_only : null
	);
	add('reviews', 'Add your Google review link', signals?.review_link);

	return { done: items.filter((item) => item.done).length, total: items.length, items };
}
