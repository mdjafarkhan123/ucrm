import { describe, expect, it } from 'vitest';
import { communicationSenderCreateSchema } from './communications.schema';

const valid = {
	domain_id: '6f1c2b7e-3a4d-4c8e-9b1a-2d3e4f5a6b7c',
	email_address: 'office@example.com',
	display_name: "Raad & Sons Roofing's Office",
	assigned_user_id: null,
	is_organization_default: true,
	allows_manual: true,
	allows_automated: true,
	idempotency_key: '0b9a7c1e-5d2f-4a3b-8c6d-1e2f3a4b5c6d'
};

describe('sender display name', () => {
	it('accepts an ordinary business name', () => {
		expect(communicationSenderCreateSchema.safeParse(valid).success).toBe(true);
	});

	it.each([
		'Pay at billing@evil.com',
		'Visit https://evil.com',
		'www.evil.com Support',
		'Roofing\r\nBcc: victim@example.com',
		'Roofing <ceo@example.com>',
		'   '
	])('rejects %j', (display_name) => {
		expect(communicationSenderCreateSchema.safeParse({ ...valid, display_name }).success).toBe(
			false
		);
	});
});
