import { z } from 'zod';

// Client onboarding A4: Jafar's setup stage editor (plan §2.1, ADR 0006). The limits mirror the database
// checks on setup_stages, so a bad value is explained here rather than refused there.

const draftRevision = {
	version_id: z.string().uuid('The draft identifier is invalid.'),
	revision: z.number().int().positive()
};

const stageSchema = z.object({
	// Null for a stage added in this draft; the database makes its key from the title.
	key: z
		.string()
		.regex(/^[a-z][a-z0-9_]*$/)
		.max(40)
		.nullable(),
	title: z
		.string()
		.trim()
		.min(2, 'Give the stage a name of at least 2 characters.')
		.max(80, 'Keep the name under 80 characters.'),
	description: z.string().trim().max(300, 'Keep the description under 300 characters.'),
	// Null shows the stage to every client.
	service_key: z
		.string()
		.regex(/^[a-z][a-z0-9_]{1,59}$/, 'Pick a service from your list.')
		.nullable()
});

export const saveSetupDraftSchema = z.object({
	...draftRevision,
	stages: z
		.array(stageSchema)
		.min(1, 'Setup needs at least one stage.')
		.max(30, 'Setup can have up to 30 stages.')
		.refine(
			(stages) => new Set(stages.map((stage) => stage.title.toLowerCase())).size === stages.length,
			'Two stages have the same name. Give each stage its own name.'
		)
});

export const setupDraftRevisionSchema = z.object(draftRevision);

/** Field errors keyed the way the page names its fields: `stages.2.title`, or `form`. */
export function setupEditorFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [issue.path.join('.') || 'form', issue.message] as const)
	);
}
