import userIcon from '@tabler/icons/outline/user.svg?raw';
import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
import usersIcon from '@tabler/icons/outline/users.svg?raw';
import mailIcon from '@tabler/icons/outline/mail.svg?raw';
import mailForwardIcon from '@tabler/icons/outline/mail-forward.svg?raw';
import bellIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';
import fileCertificateIcon from '@tabler/icons/outline/file-certificate.svg?raw';
import trashIcon from '@tabler/icons/outline/trash.svg?raw';

import { resolve } from '$app/paths';

// The Jafar Panel's Settings: the saved values, what needs attention, and the directory the Settings home
// lists and searches. Destinations that already have their own page (System emails, Email safety, the
// cleanup queue) are listed here too, so a search by purpose finds them.

export type OwnerSettings = {
	privacy_policy_url: string;
	privacy_policy_version: string;
	payment_instructions: string;
	sender_display_name: string;
	reply_to_address: string;
	alert_recipient_emails: string[];
	updated_at: string;
};
export type OwnerSettingsAttention = {
	email_sending_paused: boolean;
	unfinished_cleanups: number;
};
export type OwnerSettingsResponse = { settings: OwnerSettings; attention: OwnerSettingsAttention };
export type OwnerSettingsField = Exclude<keyof OwnerSettings, 'updated_at'>;

export class OwnerSettingsSaveError extends Error {
	constructor(
		message: string,
		readonly fieldErrors: Record<string, string>
	) {
		super(message);
	}
}

export async function fetchOwnerSettings(): Promise<OwnerSettingsResponse> {
	const response = await fetch('/api/jafar/settings');
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? 'Settings could not be loaded.');
	return result;
}

/** Saves only the fields given; everything else keeps its saved value. */
export async function saveOwnerSettings(
	fields: Partial<Pick<OwnerSettings, OwnerSettingsField>>
): Promise<OwnerSettings> {
	const response = await fetch('/api/jafar/settings', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(fields)
	});
	const result = await response.json();
	if (!response.ok) {
		throw new OwnerSettingsSaveError(
			result.error ?? 'Settings could not be saved.',
			result.field_errors ?? {}
		);
	}
	return result.settings;
}

export type SettingsStatus = {
	label: string;
	tone: 'warning' | 'critical';
};

export type SettingsDestination = {
	id: string;
	title: string;
	description: string;
	/** Other words people use for this setting, so search finds it by purpose. */
	keywords: string[];
	/** Already resolved, ready for an `href`. */
	href: string;
	icon: string;
	status?: (data: OwnerSettingsResponse) => SettingsStatus | undefined;
};

export type SettingsGroup = {
	id: string;
	title: string;
	hint: string;
	icon: string;
	/** Shown while the group has nothing to set yet: what will live here, and when it arrives. */
	upcoming?: string;
	destinations: SettingsDestination[];
};

const notSet = (missing: boolean): SettingsStatus | undefined =>
	missing ? { label: 'Not set', tone: 'warning' } : undefined;

/** The six groups, in the order Jafar approved. */
export const settingsGroups: SettingsGroup[] = [
	{
		id: 'my-preferences',
		title: 'My preferences',
		hint: 'Choices that affect only you.',
		icon: userIcon,
		upcoming: 'Your own meeting reminders arrive here with sales booking.',
		destinations: []
	},
	{
		id: 'business-booking',
		title: 'Business & booking',
		hint: 'How prospects book a sales call with Uplift.',
		icon: calendarIcon,
		upcoming:
			'Booking availability, meeting types, and your public booking link arrive here with sales booking.',
		destinations: []
	},
	{
		id: 'team-access',
		title: 'Team & access',
		hint: 'Who works in this panel and what each person can do.',
		icon: usersIcon,
		upcoming:
			'Inviting teammates and choosing what each one can see and do arrive here with team access.',
		destinations: []
	},
	{
		id: 'mail-notifications',
		title: 'Mail & notifications',
		hint: 'How Uplift’s emails look, what they say, and who hears about new activity.',
		icon: mailIcon,
		destinations: [
			{
				id: 'email-sender',
				title: 'Sender name & reply-to',
				description: 'The name prospects see on Uplift’s emails, and where their replies go.',
				keywords: ['from', 'from name', 'reply to', 'email address', 'display name'],
				href: resolve('/jafar/settings/email-sender'),
				icon: mailForwardIcon,
				status: ({ settings }) =>
					notSet(!settings.sender_display_name || !settings.reply_to_address)
			},
			{
				id: 'alerts',
				title: 'Alert recipients',
				description: 'Who gets an email when a new application arrives or something needs you.',
				keywords: ['notifications', 'owner alerts', 'new application', 'notify'],
				href: resolve('/jafar/settings/alerts'),
				icon: bellIcon,
				status: ({ settings }) => notSet(settings.alert_recipient_emails.length === 0)
			},
			{
				id: 'system-emails',
				title: 'System emails',
				description: 'The wording of the automatic emails the platform sends.',
				keywords: ['message templates', 'automatic emails', 'receipt', 'wording', 'copy'],
				href: resolve('/jafar/message-templates'),
				icon: mailIcon
			},
			{
				id: 'email-templates',
				title: 'Email templates',
				description: 'Reusable emails Uplift can send to prospects and clients.',
				keywords: ['library', 'reusable', 'canned', 'content'],
				href: resolve('/jafar/email-templates'),
				icon: fileTextIcon
			},
			{
				id: 'email-safety',
				title: 'Email safety',
				description: 'Pause or resume email sending and check that delivery is healthy.',
				keywords: ['pause', 'resume', 'sending', 'deliverability', 'bounces', 'spam'],
				href: resolve('/jafar/communications'),
				icon: shieldCheckIcon,
				status: ({ attention }) =>
					attention.email_sending_paused
						? { label: 'All email paused', tone: 'critical' }
						: undefined
			}
		]
	},
	{
		id: 'payments-client-setup',
		title: 'Payments & client setup',
		hint: 'What a new client is told about paying for their package.',
		icon: creditCardIcon,
		destinations: [
			{
				id: 'payment-instructions',
				title: 'Payment instructions',
				description: 'How to pay, shown after someone applies and in their receipt email.',
				keywords: ['bank transfer', 'pay', 'invoice', 'application received', 'receipt'],
				href: resolve('/jafar/settings/payment-instructions'),
				icon: creditCardIcon,
				status: ({ settings }) => notSet(!settings.payment_instructions)
			}
		]
	},
	{
		id: 'platform-safety',
		title: 'Platform & safety',
		hint: 'Legal details and the controls that protect client data.',
		icon: shieldLockIcon,
		destinations: [
			{
				id: 'privacy-policy',
				title: 'Privacy policy',
				description: 'The policy link and version people agree to when they apply.',
				keywords: ['legal', 'consent', 'gdpr', 'policy version', 'terms'],
				href: resolve('/jafar/settings/privacy-policy'),
				icon: fileCertificateIcon,
				status: ({ settings }) =>
					notSet(!settings.privacy_policy_url || !settings.privacy_policy_version)
			},
			{
				id: 'cleanup',
				title: 'Organization cleanup',
				description: 'Closed organizations in their 30-day recovery window, and early deletion.',
				keywords: ['delete', 'closure', 'closed', 'recovery', 'purge', 'remove organization'],
				href: resolve('/jafar/settings/cleanup'),
				icon: trashIcon,
				status: ({ attention }) =>
					attention.unfinished_cleanups > 0
						? {
								label:
									attention.unfinished_cleanups === 1
										? '1 needs a retry'
										: `${attention.unfinished_cleanups} need a retry`,
								tone: 'warning'
							}
						: undefined
			}
		]
	}
];

function normalize(text: string) {
	return text
		.toLocaleLowerCase()
		.replace(/[^\p{L}\p{N}]+/gu, ' ')
		.trim();
}

/**
 * The groups showing for a search. Every word typed must appear somewhere in a destination's name,
 * description, other words, or its group's name. An empty search shows every group, including the ones
 * with nothing to set yet; a search shows only groups with a match.
 */
export function searchSettings(groups: SettingsGroup[], query: string): SettingsGroup[] {
	const words = normalize(query).split(' ').filter(Boolean);
	if (words.length === 0) return groups;
	return groups
		.map((group) => ({
			...group,
			destinations: group.destinations.filter((destination) => {
				const haystack = normalize(
					[group.title, destination.title, destination.description, ...destination.keywords].join(
						' '
					)
				);
				return words.every((word) => haystack.includes(word));
			})
		}))
		.filter((group) => group.destinations.length > 0);
}
