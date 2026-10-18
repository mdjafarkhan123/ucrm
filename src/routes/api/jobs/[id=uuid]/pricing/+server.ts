import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	replaceJobLinesSchema,
	setJobDiscountSchema,
	setJobTaxSchema
} from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';
import { withCatalogCost } from '$lib/server/quotes/catalog-cost';

const pricingSchema = z.object({
	expected_revision: z.number().int().min(0),
	lines: z.unknown().optional(),
	discount: z.unknown().optional(),
	tax: z.unknown().optional()
});

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.edit');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = pricingSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	const { expected_revision } = parsed.data;
	if (
		parsed.data.lines === undefined &&
		parsed.data.discount === undefined &&
		parsed.data.tax === undefined
	) {
		return validationError({ form: 'Choose a pricing change to save.' });
	}

	let lines: Record<string, unknown>[] | null = null;
	if (parsed.data.lines !== undefined) {
		const checked = replaceJobLinesSchema.safeParse({
			expected_revision,
			lines: parsed.data.lines
		});
		if (!checked.success) return validationError(zodFieldErrors(checked.error));
		const priced = await withCatalogCost(
			event.locals.supabase,
			check.auth.organization.id,
			check.auth.user.id,
			checked.data.lines.map(({ source_catalog_item_id, ...line }) => ({
				...line,
				catalog_item_id: source_catalog_item_id
			}))
		);
		lines = priced.map(({ catalog_item_id, ...line }) => ({
			...line,
			source_catalog_item_id: catalog_item_id
		}));
	}

	let discount: z.infer<typeof setJobDiscountSchema> | null = null;
	if (parsed.data.discount !== undefined) {
		if (
			parsed.data.discount === null ||
			typeof parsed.data.discount !== 'object' ||
			Array.isArray(parsed.data.discount)
		) {
			return validationError({ discount: 'Choose a valid discount.' });
		}
		const checked = setJobDiscountSchema.safeParse({
			expected_revision,
			...parsed.data.discount
		});
		if (!checked.success) return validationError(zodFieldErrors(checked.error));
		discount = checked.data;
	}

	let tax: z.infer<typeof setJobTaxSchema> | null = null;
	if (parsed.data.tax !== undefined) {
		if (
			parsed.data.tax === null ||
			typeof parsed.data.tax !== 'object' ||
			Array.isArray(parsed.data.tax)
		) {
			return validationError({ tax: 'Choose a valid tax option.' });
		}
		const checked = setJobTaxSchema.safeParse({
			expected_revision,
			...parsed.data.tax
		});
		if (!checked.success) return validationError(zodFieldErrors(checked.error));
		tax = checked.data;
	}

	const { data, error } = await event.locals.supabase.rpc('save_job_pricing', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision,
		new_lines: lines,
		new_discount: discount,
		new_tax: tax
	});

	if (error) return updateJobError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
