import { z } from 'zod';
import {
	DIRECTORY_ATTENTION_REASONS,
	DIRECTORY_BILLING,
	DIRECTORY_JOINED,
	DIRECTORY_LIFECYCLES,
	DIRECTORY_PACKAGE_MAX,
	DIRECTORY_RENEWS,
	DIRECTORY_SEARCH_MAX,
	DIRECTORY_TEAM_SIZES,
	ISO_DAY,
	isPackageValue
} from '$lib/jafar/organization-directory-filters';

export const organizationAttentionReasons = DIRECTORY_ATTENTION_REASONS;

// A list arrives as one comma-separated value: `?lifecycle=active,suspended`. Every item must be allowed and
// none repeated, so a bad link is refused rather than half-applied.
function list<Value extends string>(allowed: readonly [Value, ...Value[]], max = allowed.length) {
	return z
		.string()
		.max(1000)
		.transform((raw) => raw.split(',').map((part) => part.trim()))
		.pipe(z.array(z.enum(allowed)).min(1).max(max))
		.transform((items) => [...new Set(items)]);
}

const day = z.string().regex(ISO_DAY);

export const organizationDirectoryQuerySchema = z
	.object({
		search: z.string().trim().max(DIRECTORY_SEARCH_MAX).optional(),
		attention_reason: list(DIRECTORY_ATTENTION_REASONS).optional(),
		lifecycle: list(DIRECTORY_LIFECYCLES).optional(),
		/** Package ids, plus `none` for organizations on no package. */
		package: z
			.string()
			.max(1000)
			.transform((raw) => raw.split(',').map((part) => part.trim().toLowerCase()))
			.pipe(
				z
					.array(z.string().refine(isPackageValue))
					.min(1)
					.max(DIRECTORY_PACKAGE_MAX + 1)
			)
			.transform((items) => [...new Set(items)])
			.optional(),
		billing: z.enum(DIRECTORY_BILLING).optional(),
		renews: z.enum(DIRECTORY_RENEWS).optional(),
		team: z.enum(DIRECTORY_TEAM_SIZES).optional(),
		joined: z.enum(DIRECTORY_JOINED).optional(),
		from: day.optional(),
		to: day.optional(),
		/** Opaque cursor from the previous page's `next_cursor`, base64 of `created_at|id`. */
		cursor: z.string().max(200).optional(),
		limit: z.coerce.number().int().min(1).max(100).optional()
	})
	.refine((query) => query.joined === 'custom' || (!query.from && !query.to), {
		message: 'A date range needs the custom joined option.'
	})
	.refine((query) => query.joined !== 'custom' || Boolean(query.from || query.to), {
		message: 'A custom range needs at least one date.'
	})
	.refine((query) => !query.from || !query.to || query.from <= query.to, {
		message: 'The range ends before it starts.'
	});

export type OrganizationDirectoryQuery = z.infer<typeof organizationDirectoryQuerySchema>;
