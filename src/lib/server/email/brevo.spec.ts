import { describe, expect, it } from 'vitest';
import { PLATFORM_CONTACT_EMAIL } from '$lib/account/standing';
import { SYSTEM_FROM_NAME, systemEmailSender } from './brevo';

describe('systemEmailSender', () => {
	it('shows the Uplift name and replies to the platform contact address', () => {
		expect(systemEmailSender('noreply@contact.example.com')).toEqual({
			sender: { name: SYSTEM_FROM_NAME, email: 'noreply@contact.example.com' },
			replyTo: { name: SYSTEM_FROM_NAME, email: PLATFORM_CONTACT_EMAIL }
		});
		expect(SYSTEM_FROM_NAME).toBe('Uplift');
	});
});
