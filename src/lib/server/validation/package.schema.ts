import { z } from 'zod';
import { limitKeySchema, packageKeySchema } from './access.schema';

const packageText = z.string().trim().min(1).max(500);
const allowanceSchema = z
	.object({
		state: z.enum(['unlimited', 'not_included', 'numeric']),
		value: z.number().int().positive().nullable()
	})
	.superRefine((allowance, context) => {
		if (allowance.state === 'numeric' && allowance.value === null) {
			context.addIssue({
				code: 'custom',
				path: ['value'],
				message: 'Enter at least one recipient for a numeric allowance.'
			});
		}
		if (allowance.state !== 'numeric' && allowance.value !== null) {
			context.addIssue({
				code: 'custom',
				path: ['value'],
				message: 'Only numeric allowances can include a recipient count.'
			});
		}
	});

export const packageVersionWriteSchema = z.object({
	package_key: packageKeySchema,
	version_id: z.string().uuid().optional(),
	display_name: z.string().trim().min(2).max(80),
	public_description: packageText,
	value_explanation: z.string().trim().max(500).nullable().optional(),
	price_usd_cents: z.number().int().nonnegative(),
	feature_keys: z.array(z.string().trim().min(1).max(100)).max(100).default([]),
	limit: z
		.object({
			key: limitKeySchema,
			state: z.enum(['unlimited', 'not_included', 'numeric']),
			value: z.number().int().positive().nullable().optional()
		})
		.nullable()
		.optional(),
	email_allowances: z.object({
		operational: allowanceSchema,
		essential: allowanceSchema
	}),
	website_chat_limits: z.object({
		widgets: allowanceSchema,
		accepted_conversations: allowanceSchema
	})
});

export const packageVersionPublishSchema = z.object({
	package_key: packageKeySchema,
	version_id: z.string().uuid()
});

export const packageRetireSchema = z.object({
	package_key: packageKeySchema
});
