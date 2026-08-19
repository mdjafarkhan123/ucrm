import { describe, expect, it } from 'vitest';
import {
	taskCompletionSchema,
	taskInputSchema,
	updateOpportunityExpectedCloseSchema,
	updateOpportunityNextFollowUpSchema,
	updateOpportunityValueSchema
} from './pipeline.schema';

describe('updateOpportunityValueSchema', () => {
	it('accepts a real value', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: 1250.5 });
		expect(result.success).toBe(true);
	});

	it('accepts null to clear the estimate', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: null });
		expect(result.success).toBe(true);
	});

	it('accepts zero, a real estimate someone typed', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: 0 });
		expect(result.success).toBe(true);
	});

	it('rejects a negative value', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: -1 });
		expect(result.success).toBe(false);
	});

	it('rejects a value over the ceiling', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: 10_000_000_000 });
		expect(result.success).toBe(false);
	});

	it('rejects a non-finite value', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: Infinity });
		expect(result.success).toBe(false);
	});

	it('rejects a value that is not a number', () => {
		const result = updateOpportunityValueSchema.safeParse({ estimated_value: '100' });
		expect(result.success).toBe(false);
	});

	it('rejects a missing field', () => {
		const result = updateOpportunityValueSchema.safeParse({});
		expect(result.success).toBe(false);
	});
});

describe('updateOpportunityExpectedCloseSchema', () => {
	it('accepts an ISO day', () => {
		const result = updateOpportunityExpectedCloseSchema.safeParse({
			expected_close_on: '2026-09-01'
		});
		expect(result.success).toBe(true);
	});

	it('accepts null to clear the date', () => {
		const result = updateOpportunityExpectedCloseSchema.safeParse({ expected_close_on: null });
		expect(result.success).toBe(true);
	});

	it('rejects a non-ISO date shape', () => {
		const result = updateOpportunityExpectedCloseSchema.safeParse({
			expected_close_on: '09/01/2026'
		});
		expect(result.success).toBe(false);
	});

	it('rejects a full timestamp', () => {
		const result = updateOpportunityExpectedCloseSchema.safeParse({
			expected_close_on: '2026-09-01T00:00:00.000Z'
		});
		expect(result.success).toBe(false);
	});
});

describe('updateOpportunityNextFollowUpSchema', () => {
	it('accepts an ISO day', () => {
		const result = updateOpportunityNextFollowUpSchema.safeParse({
			next_follow_up_on: '2026-09-05'
		});
		expect(result.success).toBe(true);
	});

	it('accepts null to clear the date', () => {
		const result = updateOpportunityNextFollowUpSchema.safeParse({ next_follow_up_on: null });
		expect(result.success).toBe(true);
	});

	it('rejects a non-ISO date shape', () => {
		const result = updateOpportunityNextFollowUpSchema.safeParse({
			next_follow_up_on: 'next tuesday'
		});
		expect(result.success).toBe(false);
	});
});

describe('taskInputSchema', () => {
	it('accepts a title on its own', () => {
		const result = taskInputSchema.safeParse({ title: 'Call Colin' });
		expect(result.success).toBe(true);
		expect(result.data).toEqual({
			title: 'Call Colin',
			instructions: null,
			assignee_user_id: null,
			due_on: null
		});
	});

	it('trims the title and keeps the details', () => {
		const result = taskInputSchema.safeParse({
			title: '  Call Colin  ',
			instructions: 'Ring the mobile first',
			assignee_user_id: '00000000-0000-4000-8000-000000000001',
			due_on: '2026-09-05'
		});
		expect(result.success).toBe(true);
		expect(result.data?.title).toBe('Call Colin');
		expect(result.data?.instructions).toBe('Ring the mobile first');
	});

	it('turns blank instructions into nothing at all', () => {
		const result = taskInputSchema.safeParse({ title: 'Call Colin', instructions: '   ' });
		expect(result.success).toBe(true);
		expect(result.data?.instructions).toBeNull();
	});

	it('rejects a missing title', () => {
		expect(taskInputSchema.safeParse({}).success).toBe(false);
	});

	it('rejects a title of one character, like the database does', () => {
		expect(taskInputSchema.safeParse({ title: 'x' }).success).toBe(false);
	});

	it('rejects a title past 160 characters', () => {
		expect(taskInputSchema.safeParse({ title: 'a'.repeat(161) }).success).toBe(false);
	});

	it('rejects instructions past 2000 characters', () => {
		const result = taskInputSchema.safeParse({
			title: 'Call Colin',
			instructions: 'a'.repeat(2001)
		});
		expect(result.success).toBe(false);
	});

	it('rejects an assignee that is not an id', () => {
		expect(
			taskInputSchema.safeParse({ title: 'Call Colin', assignee_user_id: 'colin' }).success
		).toBe(false);
	});

	it('rejects a due date that is not an ISO day', () => {
		expect(taskInputSchema.safeParse({ title: 'Call Colin', due_on: 'thursday' }).success).toBe(
			false
		);
	});
});

describe('taskCompletionSchema', () => {
	it('accepts both directions', () => {
		expect(taskCompletionSchema.safeParse({ completed: true }).success).toBe(true);
		expect(taskCompletionSchema.safeParse({ completed: false }).success).toBe(true);
	});

	it('rejects anything that is not a plain boolean', () => {
		expect(taskCompletionSchema.safeParse({ completed: 'yes' }).success).toBe(false);
		expect(taskCompletionSchema.safeParse({}).success).toBe(false);
	});
});
