import { z } from 'zod';

// Contractor Settings Part 6C-2: the write-envelope schemas for the draft create/save routes. These validate
// only the envelope (name, source, preset lineage, revision, idempotency key). The definition itself is
// validated against the catalog and limits by validateDefinition (src/lib/server/automation/definition.ts),
// which is the single source of catalog truth, so it is passed through here as opaque unknown.

const idempotencyKey = z.string().uuid();
const recipeName = z.string().trim().min(1).max(120);

export const createRecipeDraftSchema = z
	.object({
		name: recipeName,
		source: z.enum(['preset', 'custom']),
		preset_key: z.string().trim().min(1).max(120).nullish(),
		preset_version: z.number().int().min(1).nullish(),
		idempotency_key: idempotencyKey,
		definition: z.unknown()
	})
	.strict()
	.superRefine((value, ctx) => {
		const hasLineage = value.preset_key != null && value.preset_version != null;
		if (value.source === 'preset' && !hasLineage) {
			ctx.addIssue({
				code: z.ZodIssueCode.custom,
				path: ['preset_key'],
				message: 'A preset recipe requires its preset lineage.'
			});
		}
		if (value.source === 'custom' && (value.preset_key != null || value.preset_version != null)) {
			ctx.addIssue({
				code: z.ZodIssueCode.custom,
				path: ['preset_key'],
				message: 'A custom recipe carries no preset lineage.'
			});
		}
	});

export type CreateRecipeDraftBody = z.infer<typeof createRecipeDraftSchema>;

export const saveRecipeDraftSchema = z
	.object({
		expected_revision: z.number().int().min(1),
		name: recipeName,
		idempotency_key: idempotencyKey,
		definition: z.unknown()
	})
	.strict();

export type SaveRecipeDraftBody = z.infer<typeof saveRecipeDraftSchema>;

// Part 6C-3: the lifecycle write envelopes. Each carries the aggregate revision the actor last saw
// (optimistic lock) and a fresh idempotency key, matching the atomic command signatures. The definition is
// never sent for a lifecycle action — activation freezes the recipe's OWN saved draft, read server-side.

export const activateRecipeSchema = z
	.object({
		expected_revision: z.number().int().min(1),
		idempotency_key: idempotencyKey
	})
	.strict();

export type ActivateRecipeBody = z.infer<typeof activateRecipeSchema>;

// The closed set of state transitions handled by set_automation_recipe_lifecycle_state. `activate` and
// `duplicate` are their own routes (they need the draft/name), so they are not part of this enum.
export const lifecycleActionSchema = z
	.object({
		action: z.enum(['pause', 'resume', 'archive', 'restore']),
		expected_revision: z.number().int().min(1),
		idempotency_key: idempotencyKey
	})
	.strict();

export type LifecycleActionBody = z.infer<typeof lifecycleActionSchema>;

export const duplicateRecipeSchema = z
	.object({
		name: recipeName,
		expected_revision: z.number().int().min(1),
		idempotency_key: idempotencyKey
	})
	.strict();

export type DuplicateRecipeBody = z.infer<typeof duplicateRecipeSchema>;

// Flatten a Zod error into the field_errors map the app's validationError helper expects.
export function automationFieldErrors(error: z.ZodError): Record<string, string> {
	const fieldErrors: Record<string, string> = {};
	for (const issue of error.issues) {
		const key = issue.path.join('.') || 'form';
		if (!fieldErrors[key]) fieldErrors[key] = issue.message;
	}
	return fieldErrors;
}
