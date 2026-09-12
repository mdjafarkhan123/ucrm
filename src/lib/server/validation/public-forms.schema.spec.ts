import { describe, expect, it } from 'vitest';
import {
	buildPublicFormAnswersSchema,
	buildPublicFormContactSchema,
	publicFormEnvelopeSchema
} from './public-forms.schema';
import type { ContactBlock, FormSection } from '$lib/forms/types';

const baseContact: ContactBlock = {
	name: { required: true },
	email: { shown: true, required: true, marketing_consent: false },
	phone: { shown: false, required: false, marketing_consent: false },
	company: { shown: false, required: false },
	address: { shown: false, required: false }
};

describe('buildPublicFormContactSchema', () => {
	it('requires a name always', () => {
		const schema = buildPublicFormContactSchema(baseContact);
		expect(schema.safeParse({ name: '', email: 'a@b.com' }).success).toBe(false);
		expect(schema.safeParse({ name: 'Jane', email: 'a@b.com' }).success).toBe(true);
	});

	it('requires a shown+required field and rejects a bad email', () => {
		const schema = buildPublicFormContactSchema(baseContact);
		expect(schema.safeParse({ name: 'Jane', email: '' }).success).toBe(false);
		expect(schema.safeParse({ name: 'Jane', email: 'not-an-email' }).success).toBe(false);
	});

	it('never demands a field the form does not show', () => {
		const schema = buildPublicFormContactSchema(baseContact);
		// phone is not shown on this form -- omitting it, or sending garbage for it, must not fail.
		expect(schema.safeParse({ name: 'Jane', email: 'a@b.com' }).success).toBe(true);
	});

	it('allows an optional shown field to be left blank', () => {
		const contact: ContactBlock = {
			...baseContact,
			phone: { shown: true, required: false, marketing_consent: false }
		};
		const schema = buildPublicFormContactSchema(contact);
		expect(schema.safeParse({ name: 'Jane', email: 'a@b.com', phone: '' }).success).toBe(true);
	});

	it('requires only line1 and city on a required address, never state/postal', () => {
		const contact: ContactBlock = { ...baseContact, address: { shown: true, required: true } };
		const schema = buildPublicFormContactSchema(contact);
		const payload = { name: 'Jane', email: 'a@b.com' };
		expect(schema.safeParse({ ...payload, address: { line1: '', city: 'Austin' } }).success).toBe(
			false
		);
		expect(
			schema.safeParse({ ...payload, address: { line1: '1 Main St', city: '' } }).success
		).toBe(false);
		expect(
			schema.safeParse({ ...payload, address: { line1: '1 Main St', city: 'Austin' } }).success
		).toBe(true);
	});

	it('allows an optional address to be left entirely blank', () => {
		const contact: ContactBlock = { ...baseContact, address: { shown: true, required: false } };
		const schema = buildPublicFormContactSchema(contact);
		const result = schema.safeParse({
			name: 'Jane',
			email: 'a@b.com',
			address: { line1: '', city: '', state_region: '', postal_code: '' }
		});
		expect(result.success).toBe(true);
	});
});

describe('buildPublicFormAnswersSchema', () => {
	const sections: FormSection[] = [
		{
			id: 'sec-1',
			title: 'Details',
			questions: [
				{ id: 'q-required-text', type: 'short_text', label: 'Name of pet', required: true },
				{ id: 'q-optional-text', type: 'short_text', label: 'Notes', required: false },
				{
					id: 'q-radio',
					type: 'radio',
					label: 'Pick one',
					required: true,
					options: ['A', 'B']
				},
				{
					id: 'q-checkbox',
					type: 'checkbox',
					label: 'Pick some',
					required: false,
					options: ['X', 'Y']
				}
			]
		}
	];

	it('requires a required question and allows an optional one to be omitted', () => {
		const schema = buildPublicFormAnswersSchema(sections);
		const result = schema.safeParse({
			'q-required-text': 'Fluffy',
			'q-radio': 'A'
		});
		expect(result.success).toBe(true);
	});

	it('rejects a missing required answer', () => {
		const schema = buildPublicFormAnswersSchema(sections);
		const result = schema.safeParse({ 'q-radio': 'A' });
		expect(result.success).toBe(false);
	});

	it('rejects a choice outside the question’s own options', () => {
		const schema = buildPublicFormAnswersSchema(sections);
		const result = schema.safeParse({ 'q-required-text': 'Fluffy', 'q-radio': 'not-an-option' });
		expect(result.success).toBe(false);
	});

	it('accepts a valid multi-select subset', () => {
		const schema = buildPublicFormAnswersSchema(sections);
		const result = schema.safeParse({
			'q-required-text': 'Fluffy',
			'q-radio': 'A',
			'q-checkbox': ['X']
		});
		expect(result.success).toBe(true);
	});
});

describe('publicFormEnvelopeSchema', () => {
	it('requires a turnstile token and an idempotency key', () => {
		expect(
			publicFormEnvelopeSchema.safeParse({ turnstile_token: '', idempotency_key: '' }).success
		).toBe(false);
	});

	it('defaults contact/answers/photos when omitted', () => {
		const result = publicFormEnvelopeSchema.safeParse({
			turnstile_token: 'tok',
			idempotency_key: 'key-1'
		});
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.contact).toEqual({});
			expect(result.data.answers).toEqual({});
			expect(result.data.photo_object_keys).toEqual([]);
		}
	});
});
