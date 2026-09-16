import type { RequestHandler } from './$types';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	financialExportFileName,
	writeFinancialExport,
	type FinancialExportContext
} from '$lib/server/exports/financial-export';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { calendarDay } from '$lib/time/calendar-day';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { financialExportQuerySchema } from '$lib/server/validation/financial-reports.schema';

// Financial reconciliation, Part 3: download the accountant-ready package for a date range.
//
// Streams a zip of one CSV per ledger plus a reconciliation summary and manifest. Any invoice-money viewer may
// start it; each ledger inside is then gated by its own reader's permissions, so a caller who cannot see job
// costs, team hours or Pipeline values gets a package without those files or columns -- never with zeros.
//
// A light rate limit sits in front: one package reads every ledger for the period, and the counter stops a
// hammering loop without getting in the way of a monthly "send it to the accountant" click.
const EXPORT_LIMIT = { windowSeconds: 60, maxAttempts: 5 };

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'invoices.view');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'invoices.view_price')) {
		return new Response(
			JSON.stringify({
				error: 'You do not have access to invoice amounts.',
				reason: 'permission_denied'
			}),
			{ status: 403, headers: { 'content-type': 'application/json' } }
		);
	}

	const parsed = financialExportQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? undefined,
		to: event.url.searchParams.get('to') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `financial-export:${organizationId}`,
			...EXPORT_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const formatting = await organizationFormatting(
		event.locals.supabase as SupabaseClient<Database>,
		organizationId
	);
	if (!formatting.ok) return databaseError();

	const generatedAt = new Date();
	const context: FinancialExportContext = {
		organizationId,
		from: parsed.data.from,
		to: parsed.data.to,
		timezone: formatting.formatting.timezone,
		currencyCode: formatting.formatting.currency_code,
		agingAsOf: calendarDay(generatedAt, formatting.formatting.timezone),
		generatedAt
	};

	// The zip is produced into one side of a TransformStream and the browser reads the other, so a slow
	// download slows the database reads instead of piling chunks up in memory. A reader failure mid-way
	// aborts the stream: the browser reports a failed download and the person tries again.
	const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
	const writer = writable.getWriter();
	void writeFinancialExport(event.locals.supabase, check.access, context, (chunk) =>
		writer.write(chunk)
	)
		.then(() => writer.close())
		.catch((error) => {
			console.error('Could not build the accounting export.', error);
			return writer.abort(error);
		});

	return new Response(readable, {
		headers: {
			'content-type': 'application/zip',
			'content-disposition': `attachment; filename="${financialExportFileName(parsed.data.from, parsed.data.to)}"`,
			'cache-control': 'no-store'
		}
	});
};
