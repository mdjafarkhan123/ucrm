import { describe, expect, it } from 'vitest';
import { searchSettings, settingsGroups, type OwnerSettingsResponse } from './owner-settings';

const complete: OwnerSettingsResponse = {
	settings: {
		privacy_policy_url: 'https://example.com/privacy',
		privacy_policy_version: 'v1',
		payment_instructions: 'Pay by bank transfer.',
		sender_display_name: 'Uplift',
		reply_to_address: 'hello@example.com',
		alert_recipient_emails: ['owner@example.com'],
		updated_at: '2026-10-07T00:00:00Z'
	},
	attention: { email_sending_paused: false, unfinished_cleanups: 0 }
};

const destinations = settingsGroups.flatMap((group) => group.destinations);
const titles = (groups: typeof settingsGroups) =>
	groups.flatMap((group) => group.destinations.map((destination) => destination.title));
const statusOf = (id: string, data: OwnerSettingsResponse) =>
	destinations.find((destination) => destination.id === id)?.status?.(data);

describe('Jafar Settings directory', () => {
	it('keeps the six approved groups in order', () => {
		expect(settingsGroups.map((group) => group.title)).toEqual([
			'My preferences',
			'Business & booking',
			'Team & access',
			'Mail & notifications',
			'Payments & client setup',
			'Platform & safety'
		]);
	});

	it('says what is coming for every group that has nothing to set yet', () => {
		for (const group of settingsGroups) {
			if (group.destinations.length === 0) expect(group.upcoming).toBeTruthy();
		}
	});

	it('gives every destination a unique id and link', () => {
		expect(new Set(destinations.map((d) => d.id)).size).toBe(destinations.length);
		expect(new Set(destinations.map((d) => d.href)).size).toBe(destinations.length);
	});
});

describe('searchSettings', () => {
	it('shows every group, including empty ones, when nothing is typed', () => {
		expect(searchSettings(settingsGroups, '   ')).toBe(settingsGroups);
	});

	it('finds the sender setting by "sender"', () => {
		expect(titles(searchSettings(settingsGroups, 'sender'))).toEqual(['Sender name & reply-to']);
	});

	it('finds a setting by another word for its purpose, ignoring case and punctuation', () => {
		expect(titles(searchSettings(settingsGroups, 'Bank-Transfer'))).toEqual([
			'Payment instructions'
		]);
		expect(titles(searchSettings(settingsGroups, 'gdpr'))).toEqual(['Privacy policy']);
		expect(titles(searchSettings(settingsGroups, 'pause'))).toEqual(['Email safety']);
	});

	it('needs every typed word to match', () => {
		expect(titles(searchSettings(settingsGroups, 'reply alerts'))).toEqual([]);
	});

	it('drops groups with no match, and groups with nothing to set yet', () => {
		const groups = searchSettings(settingsGroups, 'privacy');
		expect(groups.map((group) => group.title)).toEqual(['Platform & safety']);
	});
});

describe('needs-attention marks', () => {
	it('marks nothing when every setting is filled in and nothing is waiting', () => {
		expect(destinations.map((d) => d.status?.(complete)).filter(Boolean)).toEqual([]);
	});

	it('marks a blank sender, reply-to, payment, privacy, or empty alert list as not set', () => {
		const blank = (patch: Partial<OwnerSettingsResponse['settings']>) => ({
			...complete,
			settings: { ...complete.settings, ...patch }
		});
		expect(statusOf('email-sender', blank({ reply_to_address: '' }))?.label).toBe('Not set');
		expect(statusOf('alerts', blank({ alert_recipient_emails: [] }))?.label).toBe('Not set');
		expect(statusOf('payment-instructions', blank({ payment_instructions: '' }))?.label).toBe(
			'Not set'
		);
		expect(statusOf('privacy-policy', blank({ privacy_policy_version: '' }))?.label).toBe(
			'Not set'
		);
	});

	it('marks paused email as critical and counts cleanups waiting for a retry', () => {
		const waiting = {
			...complete,
			attention: { email_sending_paused: true, unfinished_cleanups: 2 }
		};
		expect(statusOf('email-safety', waiting)).toEqual({
			label: 'All email paused',
			tone: 'critical'
		});
		expect(statusOf('cleanup', waiting)?.label).toBe('2 need a retry');
		expect(
			statusOf('cleanup', {
				...complete,
				attention: { ...complete.attention, unfinished_cleanups: 1 }
			})?.label
		).toBe('1 needs a retry');
	});
});
