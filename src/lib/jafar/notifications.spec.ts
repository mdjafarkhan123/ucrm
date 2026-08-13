import { describe, expect, it } from 'vitest';
import { notificationLinkPath, type NotificationTarget } from './notification-links';
import { notificationHref, relativeTime, severityLabel } from './notifications';

describe('owner notification presentation helpers', () => {
	it('sends every target kind to the same place the alert email does', () => {
		expect(
			notificationHref({ target_kind: 'onboarding_application', target_id: 'app-1' })
		).toContain('/jafar/prospects?application=app-1');
		expect(notificationHref({ target_kind: 'organization', target_id: 'org-1' })).toContain(
			'/jafar/organizations/org-1'
		);
		expect(notificationHref({ target_kind: 'operation_attempt', target_id: 'op-1' })).toContain(
			'/jafar/operations?operation=op-1'
		);
	});

	it('falls back to the panel itself when a notification is not about one record', () => {
		expect(notificationHref({ target_kind: 'platform', target_id: null })).toContain('/jafar');
	});

	// The panel and the alert emails build their links separately, so this is the guard that
	// keeps them from ever drifting apart.
	it('always agrees with the link the alert email uses', () => {
		const targets: NotificationTarget[] = [
			{ target_kind: 'onboarding_application', target_id: 'app-1' },
			{ target_kind: 'organization', target_id: 'org-1' },
			{ target_kind: 'operation_attempt', target_id: 'op-1' },
			{ target_kind: 'platform', target_id: null }
		];
		for (const target of targets) {
			expect(notificationHref(target)).toBe(notificationLinkPath(target));
		}
	});

	it('describes recent times in a glanceable way', () => {
		const now = new Date('2026-08-13T12:00:00Z').getTime();
		expect(relativeTime('2026-08-13T11:58:00Z', now)).toMatch(/2 minutes ago/i);
		expect(relativeTime('2026-08-13T09:00:00Z', now)).toMatch(/3 hours ago/i);
		expect(relativeTime('2026-08-11T12:00:00Z', now)).toMatch(/2 days ago/i);
	});

	it('never shows a broken timestamp when a date cannot be read', () => {
		expect(relativeTime('not-a-date')).toBe('');
	});

	it('labels severity in words Jafar can act on', () => {
		expect(severityLabel('info')).toBe('Update');
		expect(severityLabel('attention')).toBe('Needs attention');
		expect(severityLabel('urgent')).toBe('Urgent');
	});
});
