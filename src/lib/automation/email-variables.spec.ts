import { describe, expect, it } from 'vitest';
import {
	automationEmailBodySchema,
	automationEmailSubjectSchema,
	automationSmsBodySchema,
	unknownEmailVariables,
	unknownSmsVariables
} from './email-variables';

describe('unknownEmailVariables', () => {
	it('accepts every allow-listed token', () => {
		const text =
			'Hi {{customer_name}} from {{business_name}}, quote {{quote_number}}: {{quote_link}}';
		expect(unknownEmailVariables(text)).toEqual([]);
	});

	it('names each unknown token once, in order', () => {
		expect(unknownEmailVariables('{{price}} then {{secret}} then {{price}}')).toEqual([
			'price',
			'secret'
		]);
	});

	it('treats an inner-whitespace token as unknown so it cannot slip past the exact SQL replace', () => {
		expect(unknownEmailVariables('{{ customer_name }}')).toEqual([' customer_name ']);
	});
});

describe('automationEmailBodySchema', () => {
	it('accepts author text with only safe variables', () => {
		expect(automationEmailBodySchema.safeParse('Hello {{customer_name}}').success).toBe(true);
	});

	it('rejects an unknown variable with a plain message', () => {
		const result = automationEmailBodySchema.safeParse('Pay {{account_number}} now');
		expect(result.success).toBe(false);
		if (!result.success) expect(result.error.issues[0].message).toContain('{{account_number}}');
	});

	it('rejects an empty body', () => {
		expect(automationEmailBodySchema.safeParse('   ').success).toBe(false);
	});
});

describe('automationEmailSubjectSchema', () => {
	it('accepts a single line with safe variables', () => {
		expect(automationEmailSubjectSchema.safeParse('Your quote {{quote_number}}').success).toBe(
			true
		);
	});

	it('rejects a multi-line subject', () => {
		expect(automationEmailSubjectSchema.safeParse('line one\nline two').success).toBe(false);
	});
});

describe('unknownSmsVariables', () => {
	it('accepts the three tokens SMS supports', () => {
		const text = 'Hi {{customer_name}} from {{business_name}}, quote {{quote_number}}';
		expect(unknownSmsVariables(text)).toEqual([]);
	});

	it('treats quote_link as unknown: SMS does not mint a customer link yet', () => {
		expect(unknownSmsVariables('See it here: {{quote_link}}')).toEqual(['quote_link']);
	});
});

describe('automationSmsBodySchema', () => {
	it('accepts author text with only SMS-safe variables', () => {
		expect(automationSmsBodySchema.safeParse('Hi {{customer_name}}, following up').success).toBe(
			true
		);
	});

	it('rejects {{quote_link}} even though email allows it', () => {
		const result = automationSmsBodySchema.safeParse('Approve here: {{quote_link}}');
		expect(result.success).toBe(false);
		if (!result.success) expect(result.error.issues[0].message).toContain('{{quote_link}}');
	});

	it('rejects an empty body', () => {
		expect(automationSmsBodySchema.safeParse('   ').success).toBe(false);
	});
});
