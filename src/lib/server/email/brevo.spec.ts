import { describe, expect, it } from 'vitest';
import { SYSTEM_FROM_NAME, systemEmailSender } from './brevo';

describe('systemEmailSender', () => {
	it('shows the Uplift name and sets no Reply-To until a mailbox is configured', () => {
		expect(systemEmailSender('noreply@contact.example.com')).toEqual({
			sender: { name: SYSTEM_FROM_NAME, email: 'noreply@contact.example.com' }
		});
		expect(SYSTEM_FROM_NAME).toBe('Uplift');
	});

	it('adds the Reply-To when a mailbox is configured', () => {
		expect(systemEmailSender('noreply@contact.example.com', 'info@example.com')).toEqual({
			sender: { name: SYSTEM_FROM_NAME, email: 'noreply@contact.example.com' },
			replyTo: { name: SYSTEM_FROM_NAME, email: 'info@example.com' }
		});
	});
});
