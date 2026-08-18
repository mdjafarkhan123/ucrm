import { describe, expect, it } from 'vitest';
import { normalizeEmail, normalizePhone, readWriteFailure } from './duplicates';
import {
	clientWriteSchema,
	deriveClientDisplayName
} from '$lib/server/validation/foundation.schema';

describe('contact normalization', () => {
	it('matches the database rule for email', () => {
		expect(normalizeEmail('  ZZ.Test@Example.COM ')).toBe('zz.test@example.com');
		expect(normalizeEmail('   ')).toBeNull();
		expect(normalizeEmail(null)).toBeNull();
	});

	it('matches the database rule for phone', () => {
		expect(normalizePhone('(555) 010-9999')).toBe('5550109999');
		expect(normalizePhone('+1 555 010 9999')).toBe('15550109999');
		expect(normalizePhone('no digits here')).toBeNull();
	});
});

describe('reading a failed write', () => {
	const duplicate = (kind: 'email' | 'phone') => ({
		code: '23505',
		message:
			'duplicate key value violates unique constraint "client_contact_methods_org_value_unique_idx"',
		details: `Key (organization_id, kind, normalized_value)=(0d1f, ${kind}, someone) already exists.`
	});

	it('names the field a duplicate clashed on', () => {
		expect(readWriteFailure(duplicate('email'))).toEqual({ kind: 'duplicate', field: 'email' });
		expect(readWriteFailure(duplicate('phone'))).toEqual({ kind: 'duplicate', field: 'phone' });
	});

	it('leaves the per-client unique index as a plain database failure', () => {
		expect(
			readWriteFailure({
				code: '23505',
				message:
					'duplicate key value violates unique constraint "client_contact_methods_value_unique_idx"'
			})
		).toEqual({ kind: 'database' });
	});

	it('separates a missing client from a broken rule', () => {
		expect(readWriteFailure({ code: 'P0002', message: 'That client could not be found.' })).toEqual(
			{
				kind: 'not_found'
			}
		);
		expect(
			readWriteFailure({ code: '23514', message: 'A customer cannot be changed back to a lead.' })
		).toEqual({ kind: 'rule', message: 'A customer cannot be changed back to a lead.' });
	});
});

describe('client write rules', () => {
	const person = {
		client_type: 'person' as const,
		first_name: 'Dana',
		last_name: 'Rivera'
	};

	it('requires both names for a person', () => {
		const parsed = clientWriteSchema.safeParse({ client_type: 'person', first_name: 'Dana' });
		expect(parsed.success).toBe(false);
		if (!parsed.success) {
			expect(parsed.error.issues.map((issue) => issue.path.join('.'))).toContain('last_name');
		}
	});

	it('requires a company name for a company', () => {
		const parsed = clientWriteSchema.safeParse({ client_type: 'company' });
		expect(parsed.success).toBe(false);
		if (!parsed.success) {
			expect(parsed.error.issues.map((issue) => issue.path.join('.'))).toContain('company_name');
		}
	});

	it('accepts a company without contact-person names', () => {
		const parsed = clientWriteSchema.safeParse({
			client_type: 'company',
			company_name: 'Rivera Roofing'
		});
		expect(parsed.success).toBe(true);
	});

	it('defaults to a lead who may be contacted normally', () => {
		const parsed = clientWriteSchema.parse(person);
		expect(parsed.lifecycle_status).toBe('lead');
		expect(parsed.preferences.contact_policy).toBe('allow');
		expect(parsed.preferences.review_requests).toBe(true);
		expect(parsed.preferences.marketing).toBe(false);
		expect(parsed.tag_ids).toEqual([]);
	});

	it('saves without an address but refuses a half-filled one', () => {
		expect(clientWriteSchema.safeParse(person).success).toBe(true);

		const partial = clientWriteSchema.safeParse({
			...person,
			property: { postal_code: '12345' }
		});
		expect(partial.success).toBe(false);
		if (!partial.success) {
			const fields = partial.error.issues.map((issue) => issue.path.join('.'));
			expect(fields).toContain('property.address_line1');
			expect(fields).toContain('property.city');
		}
	});

	it('derives the display name from the chosen client type', () => {
		expect(deriveClientDisplayName(clientWriteSchema.parse(person))).toBe('Dana Rivera');
		expect(
			deriveClientDisplayName(
				clientWriteSchema.parse({
					client_type: 'company',
					company_name: 'Rivera Roofing',
					first_name: 'Dana'
				})
			)
		).toBe('Rivera Roofing');
	});
});
