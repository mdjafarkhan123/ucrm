import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { updateJobDetailsSchema } from '$lib/server/validation/jobs.schema';
import { updateJobError } from '$lib/server/jobs/errors';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { asMoneyMap, withMoney } from '$lib/server/quotes/money';

const toNumber = (value: unknown): number =>
	typeof value === 'number' ? value : Number(value ?? 0);

// One job in full: identity and derived status from the same `job_list_rows` view the list draws, its own
// scope lines and visits, and its money in one gated call. Nothing here re-derives a status, and money never
// rides off the job or line rows directly — `job_money` and `job_line_money` check jobs.view_price and
// jobs.view_cost for themselves, so a reader without the grant simply gets no numbers rather than a wrong one.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const jobId = event.params.id;
	const canEdit = hasPermission(check.access, 'jobs.edit');
	const canSchedule = hasPermission(check.access, 'jobs.schedule');
	const canSeePrice = hasPermission(check.access, 'jobs.view_price');
	const canSeeCost = hasPermission(check.access, 'jobs.view_cost');

	const [listRow, jobRow, lineRows, visitRows, ruleRow, jobMoney, lineMoney, formatting] =
		await Promise.all([
			supabase
				.from('job_list_rows')
				.select(
					`id, job_number, title, job_type, is_as_needed, status, derived_status, price_basis,
				 billing_timing, currency_code, contract_start_date, contract_end_date, quote_id, created_at,
				 client_id, client_display_name, client_company_name,
				 property_id, property_label, property_address_line1, property_city, property_state_region,
				 property_postal_code`
				)
				.eq('organization_id', organizationId)
				.eq('id', jobId)
				.maybeSingle(),
			// Instructions and the revision the editor guards on live on the job row; the client's contact methods
			// and the property's second address line ride along through the job's own foreign keys, each subject
			// to the reader's RLS — a member without customers.view gets a null client here just as the list view
			// gives them an empty client name.
			supabase
				.from('jobs')
				.select(
					`instructions, revision,
				 client:clients(contact_methods:client_contact_methods(kind, value, is_primary)),
				 property:properties(address_line2)`
				)
				.eq('organization_id', organizationId)
				.eq('id', jobId)
				.maybeSingle(),
			// `authenticated` holds no grant on the money columns of `job_line_items` — price and cost reach a
			// reader only through `job_line_money` below, which checks the grants for itself — so the direct select
			// stays on the columns a crew member is allowed to read straight off the row.
			supabase
				.from('job_line_items')
				.select(
					`id, position, source_catalog_item_id, line_kind, category, is_labor, name, description,
				 unit_label, quantity, is_taxable, image_attachment_id`
				)
				.eq('organization_id', organizationId)
				.eq('job_id', jobId)
				.order('position', { ascending: true }),
			supabase
				.from('job_visits')
				.select(
					`id, position, visit_date, start_time, end_time, all_day, title, instructions, completed_at,
				 revision, assignments:job_visit_assignments(user_id)`
				)
				.eq('organization_id', organizationId)
				.eq('job_id', jobId)
				.order('position', { ascending: true }),
			// A recurring job's repeat rule, so "Edit all visits" opens on the schedule the job actually has
			// rather than an empty form. Members hold a select grant on this table; only the commands write it.
			// A one-off job has no row here, and `maybeSingle` returns null rather than an error for that.
			supabase
				.from('job_recurrence_rules')
				.select(
					`frequency, interval_count, weekdays, monthly_mode, month_day, ordinal_week, ordinal_weekday,
				 start_date, end_mode, duration_count, duration_unit, end_date, start_time, end_time, all_day`
				)
				.eq('organization_id', organizationId)
				.eq('job_id', jobId)
				.maybeSingle(),
			canSeePrice
				? supabase.rpc('job_money', { target_job_ids: [jobId] })
				: Promise.resolve({ data: {}, error: null }),
			canSeePrice
				? supabase.rpc('job_line_money', { target_job_id: jobId })
				: Promise.resolve({ data: {}, error: null }),
			organizationFormatting(supabase, organizationId)
		]);

	if (
		listRow.error ||
		jobRow.error ||
		lineRows.error ||
		visitRows.error ||
		ruleRow.error ||
		jobMoney.error ||
		lineMoney.error
	) {
		return databaseError();
	}
	// The list view is the source of truth that the job exists and is visible to this reader. No row means
	// no job here, whether it never existed or belongs to another tenant — a stranger cannot tell which.
	if (!listRow.data) return notFound('That job could not be found.');

	const row = listRow.data;
	const extra = jobRow.data as {
		instructions: string | null;
		revision: number;
		// Contact details are normalised into `client_contact_methods`, not columns on `clients`, so they ride
		// along as the client's primary rows and the header reads the primary email and phone out of them.
		client: {
			contact_methods: { kind: string; value: string | null; is_primary: boolean }[];
		} | null;
		property: { address_line2: string | null } | null;
	} | null;

	const primaryContact = (kind: 'email' | 'phone') =>
		(extra?.client?.contact_methods ?? []).find(
			(method) => method.is_primary && method.kind === kind
		)?.value ?? null;

	const money = (() => {
		if (!canSeePrice) return null;
		const entry = asMoneyMap(jobMoney.data)[jobId];
		if (!entry) return null;
		return {
			subtotal_minor: toNumber(entry.subtotal_minor),
			discount_minor: toNumber(entry.discount_minor),
			discount_name: (entry.discount_name as string | null) ?? null,
			tax_minor: toNumber(entry.tax_minor),
			tax_name: (entry.tax_name as string | null) ?? null,
			total_minor: toNumber(entry.total_minor),
			cost_minor: canSeeCost && entry.cost_minor != null ? toNumber(entry.cost_minor) : null,
			profit_minor: canSeeCost && entry.profit_minor != null ? toNumber(entry.profit_minor) : null
		};
	})();

	const visits = (visitRows.data ?? []).map((visit) => ({
		id: visit.id,
		position: visit.position,
		visit_date: visit.visit_date,
		start_time: visit.start_time,
		end_time: visit.end_time,
		all_day: visit.all_day,
		title: visit.title,
		instructions: visit.instructions,
		completed_at: visit.completed_at,
		revision: visit.revision,
		assignee_ids: ((visit.assignments ?? []) as { user_id: string }[]).map((a) => a.user_id)
	}));

	// The rule as the recurrence form holds it. Nulls stay nulls so the form's own defaults apply, and the
	// weekday array is normalised to numbers because a smallint[] can arrive as strings.
	const recurrence = ruleRow.data
		? {
				frequency: ruleRow.data.frequency,
				interval_count: ruleRow.data.interval_count,
				weekdays: (ruleRow.data.weekdays ?? []).map(toNumber),
				monthly_mode: ruleRow.data.monthly_mode,
				month_day: ruleRow.data.month_day,
				ordinal_week: ruleRow.data.ordinal_week,
				ordinal_weekday: ruleRow.data.ordinal_weekday,
				start_date: ruleRow.data.start_date,
				end_mode: ruleRow.data.end_mode,
				duration_count: ruleRow.data.duration_count,
				duration_unit: ruleRow.data.duration_unit,
				end_date: ruleRow.data.end_date,
				start_time: ruleRow.data.start_time,
				end_time: ruleRow.data.end_time,
				all_day: ruleRow.data.all_day
			}
		: null;

	return json(
		{
			recurrence,
			job: {
				id: row.id,
				job_number: row.job_number,
				title: row.title,
				job_type: row.job_type,
				is_as_needed: row.is_as_needed,
				status: row.status,
				derived_status: row.derived_status,
				price_basis: row.price_basis,
				billing_timing: row.billing_timing,
				currency_code: row.currency_code,
				instructions: extra?.instructions ?? null,
				contract_start_date: row.contract_start_date,
				contract_end_date: row.contract_end_date,
				created_at: row.created_at,
				revision: extra?.revision ?? 0,
				from_quote: row.quote_id !== null,
				client: row.client_id
					? {
							id: row.client_id,
							display_name: row.client_display_name,
							company_name: row.client_company_name,
							email: primaryContact('email'),
							phone: primaryContact('phone')
						}
					: null,
				property: row.property_id
					? {
							id: row.property_id,
							label: row.property_label,
							address_line1: row.property_address_line1,
							address_line2: extra?.property?.address_line2 ?? null,
							city: row.property_city,
							state_region: row.property_state_region,
							postal_code: row.property_postal_code
						}
					: null
			},
			lines: withMoney(
				(lineRows.data ?? []) as unknown as Array<{ id: string }>,
				canSeePrice ? asMoneyMap(lineMoney.data) : {}
			),
			visits,
			money,
			locale: formatting.ok ? formatting.formatting.locale : 'en-US',
			can_edit: canEdit,
			can_schedule: canSchedule,
			can_see_price: canSeePrice,
			can_see_cost: canSeeCost
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Staged edit of a job's title and instructions. Scope, visits, and billing each have their own command in
// later parts; this one changes only the two fields the detail page's header and its instructions carry. The
// command `update_job_details` checks jobs.edit itself, refuses a stale revision so two editors cannot
// silently overwrite each other, appends a history event, and hands back the new revision for the next save.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = updateJobDetailsSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_job_details', {
		target_organization_id: check.auth.organization.id,
		target_job_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_title: parsed.data.title,
		new_instructions: parsed.data.instructions
	});

	if (error) return updateJobError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};
