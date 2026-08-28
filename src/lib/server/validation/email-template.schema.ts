import { z } from 'zod';

// Matches the platform_packages.package_key check constraint (`starter`, `growth`, `elite`) -- kept as a
// literal enum here the same way message-template.schema.ts derives its enum from a fixed TS list, since
// both are small closed sets that change rarely enough to not warrant a runtime lookup on every request.
export const packageKeySchema = z.enum(['starter', 'growth', 'elite']);

const emailTemplateFields = {
	name: z.string().trim().min(1, 'Enter a template name.').max(120),
	folder: z.string().trim().max(60).nullish(),
	subject: z.string().trim().min(1, 'Enter a subject line.').max(300),
	body: z.string().trim().min(1, 'Enter the template body.').max(50000),
	// Empty or omitted = visible to every package. A non-empty list restricts visibility to those tiers.
	package_keys: z.array(packageKeySchema).max(3).optional()
};

export const emailTemplateCreateSchema = z.object(emailTemplateFields);

export const emailTemplateUpdateSchema = z.object(emailTemplateFields).partial();
