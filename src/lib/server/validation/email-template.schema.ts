import { z } from 'zod';

const emailTemplateFields = {
	name: z.string().trim().min(1, 'Enter a template name.').max(120),
	folder: z.string().trim().max(60).nullish(),
	subject: z.string().trim().min(1, 'Enter a subject line.').max(300),
	body: z.string().trim().min(1, 'Enter the template body.').max(50000),
	// Empty or omitted = visible to every package. A non-empty list restricts visibility to those packages;
	// a restriction names the package, so it carries over to each new edition.
	package_ids: z.array(z.string().uuid()).max(50).optional()
};

export const emailTemplateCreateSchema = z.object(emailTemplateFields);

export const emailTemplateUpdateSchema = z.object(emailTemplateFields).partial();
