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
import type { JobCosting } from '$lib/jobs/api';

const toNumber = (value: unknown): number =>
	typeof value === 'number' ? value : Number(value ?? 0);

// One job in full: identity and derived status from the same `job_list_rows` view the list draws, its own
// scope lines and visits, its selling money and its costing in gated calls. Nothing here re-derives a status,
// and money never rides off the job or line rows directly — `job_money` and `job_line_money` check
// jobs.view_price and `job_costing` checks jobs.view_cost for themselves, so a reader without the grant
// simply gets no numbers rather than a wrong one.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const jobId = event.params.id;
	const canEdit = hasPermission(check.access, 'jobs.edit');
	const canSchedule = hasPermission(check.access, 'jobs.schedule');
	const canComplete = hasPermission(check.access, 'jobs.complete');
	const canClose = hasPermission(check.access, 'jobs.close');
	const canSeePrice = hasPermission(check.access, 'jobs.view_price');
	const canSeeCost = hasPermission(check.access, 'jobs.view_cost');
	// The header's "Create invoice" entry point. Billing checks `invoices.create` for itself, so the menu
	// only offers what the member could actually do; the same right gates the billable-work lookup.
	const canInvoice = hasPermission(check.access, 'invoices.create');
	// The per-visit billing card additionally needs to know which visits are already billed, which is a fact
	// about invoices rather than about jobs — gated on invoices.view the same way the invoice screens gate it.
	const canSeeInvoiceStatus = canInvoice && hasPermission(check.access, 'invoices.view');
	// Saving a one-off tax rate into the organization's shared list is a settings right, not a jobs one. The
	// card only offers the checkbox when it is held; the command checks it again for itself.
	const canManageTaxes = hasPermission(check.access, 'settings.taxes.manage');

	const [
		listRow,
		jobRow,
		lineRows,
		visitRows,
		ruleRow,
		reminderRows,
		jobMoney,
		lineMoney,
		jobCosting,
		formatting,
		billedVisitRows,
		scheduleStages
	] = await Promise.all([
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
		// The job's open invoice reminders, oldest due date first. These are internal to-dos, carry no
		// money, and any member who may see the job may see them (their RLS asks only for jobs.view), so
		// they ride along on the detail read rather than behind a second gated call. Resolved ones are
		// history and live in the job's events rail, not here.
		supabase
			.from('job_invoice_reminders')
			.select('id, reminder_kind, due_on, note')
			.eq('organization_id', organizationId)
			.eq('job_id', jobId)
			.eq('status', 'pending')
			.order('due_on', { ascending: true }),
		canSeePrice
			? supabase.rpc('job_money', { target_job_ids: [jobId] })
			: Promise.resolve({ data: {}, error: null }),
		canSeePrice
			? supabase.rpc('job_line_money', { target_job_id: jobId })
			: Promise.resolve({ data: {}, error: null }),
		// The Job costing card: item, labor and expense cost folded into one profit for a one-off job.
		// `job_costing` is definer and checks jobs.view_cost for itself, so a reader without it is simply not
		// asked. It is its own call rather than a branch of `job_money` because the job list reads `job_money`
		// once per page and has no use for a per-job labor and expense aggregate.
		canSeeCost
			? supabase.rpc('job_costing', {
					target_organization_id: organizationId,
					target_job_id: jobId
				})
			: Promise.resolve({ data: null, error: null }),
		organizationFormatting(supabase, organizationId),
		// Which of this job's visits an invoice already claims. Scoped to one job and served by
		// invoice_sources_job_idx, the same index the claim command itself relies on.
		canSeeInvoiceStatus
			? supabase
					.from('invoice_sources')
					.select('visit_id')
					.eq('organization_id', organizationId)
					.eq('job_id', jobId)
					.eq('source_kind', 'visit')
			: Promise.resolve({ data: [], error: null }),
		// A one-off job's payment stages with their money and the bill each one produced. Definer, and it
		// applies jobs.view_price and invoices.view for itself, so a reader who may see less simply gets
		// less rather than a second round trip. Recurring work never carries a schedule.
		supabase.rpc('job_schedule_stages', { target_job_id: jobId })
	]);

	if (
		listRow.error ||
		jobRow.error ||
		lineRows.error ||
		visitRows.error ||
		ruleRow.error ||
		reminderRows.error ||
		jobMoney.error ||
		lineMoney.error ||
		jobCosting.error ||
		billedVisitRows.error ||
		scheduleStages.error
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
			// The discount and tax as they were configured, not just what they came to. The rail's two cards
			// open on the choice already made, and both ride the same jobs.view_price gate as the amounts.
			discount_type: (entry.discount_type as 'fixed' | 'percentage' | null) ?? null,
			discount_value: entry.discount_value != null ? toNumber(entry.discount_value) : null,
			tax_minor: toNumber(entry.tax_minor),
			tax_name: (entry.tax_name as string | null) ?? null,
			tax_source: (entry.tax_source as string | null) ?? 'not_configured',
			tax_rate_id: (entry.tax_rate_id as string | null) ?? null,
			tax_rate_basis_points: toNumber(entry.tax_rate_basis_points),
			total_minor: toNumber(entry.total_minor)
		};
	})();

	// The job's costing: item, labor and expense cost against revenue before tax. The reader already applied
	// jobs.view_cost, so a null here means the member may not see it. A one-off job is measured over its whole
	// life; a recurring job (`per_visit` or `fixed_per_period`) is measured over the last 30 days, and its
	// revenue, profit and margin are null when nothing in that window defines a price to state.
	const costing = ((): JobCosting | null => {
		if (!canSeeCost) return null;
		const answer = jobCosting.data as Record<string, unknown> | null;
		if (!answer || typeof answer !== 'object') return null;
		const nullableMinor = (value: unknown) => (value == null ? null : toNumber(value));
		if (answer.costing_basis === 'per_visit' || answer.costing_basis === 'fixed_per_period') {
			return {
				costing_basis: answer.costing_basis,
				job_closed: Boolean(answer.job_closed),
				window_start: String(answer.window_start),
				window_end: String(answer.window_end),
				unit_kind: answer.unit_kind === 'visits' ? 'visits' : 'periods',
				unit_count: toNumber(answer.unit_count),
				revenue_minor: nullableMinor(answer.revenue_minor),
				item_cost_minor: toNumber(answer.item_cost_minor),
				labor_cost_minor: toNumber(answer.labor_cost_minor),
				expense_cost_minor: toNumber(answer.expense_cost_minor),
				total_cost_minor: toNumber(answer.total_cost_minor),
				profit_minor: nullableMinor(answer.profit_minor),
				margin_basis_points: nullableMinor(answer.margin_basis_points),
				unrated_labor_count: toNumber(answer.unrated_labor_count),
				labor_line_and_time: Boolean(answer.labor_line_and_time)
			};
		}
		return {
			costing_basis: 'one_off',
			job_closed: Boolean(answer.job_closed),
			revenue_minor: toNumber(answer.revenue_minor),
			item_cost_minor: toNumber(answer.item_cost_minor),
			labor_cost_minor: toNumber(answer.labor_cost_minor),
			expense_cost_minor: toNumber(answer.expense_cost_minor),
			total_cost_minor: toNumber(answer.total_cost_minor),
			profit_minor: toNumber(answer.profit_minor),
			margin_basis_points: nullableMinor(answer.margin_basis_points),
			unrated_labor_count: toNumber(answer.unrated_labor_count),
			labor_line_and_time: Boolean(answer.labor_line_and_time)
		};
	})();

	const billedVisitIds = new Set(
		(billedVisitRows.data ?? []).map((claim) => claim.visit_id as string)
	);

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
		assignee_ids: ((visit.assignments ?? []) as { user_id: string }[]).map((a) => a.user_id),
		// Only meaningful when canSeeInvoiceStatus computed it; false for a reader who cannot see invoices,
		// which the visits-to-bill card never renders for anyway (it is gated on the same right).
		invoiced: billedVisitIds.has(visit.id)
	}));

	// The organisation's own calendar day, worked out in its timezone — the same clock the database uses to
	// decide Requires invoicing — so the card can tell a reminder that is already due from one still to come
	// without the browser's local timezone ever disagreeing with the status on the page. en-CA formats a date
	// as YYYY-MM-DD, matching the due_on strings the reminders carry.
	const timezone = formatting.ok ? formatting.formatting.timezone : 'UTC';
	const organizationToday = new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(
		new Date()
	);

	const reminders = (reminderRows.data ?? []).map((reminder) => ({
		id: reminder.id,
		reminder_kind: reminder.reminder_kind,
		due_on: reminder.due_on,
		note: reminder.note
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

	// The payment schedule, present only when the job actually has one. The reader has already applied every
	// gate, so this passes its answer straight through rather than second-guessing which fields survived.
	const scheduleAnswer = (scheduleStages.data ?? {}) as {
		reconciles?: boolean | null;
		job_total_minor?: number | null;
		stages?: unknown[];
	};
	const schedule =
		(scheduleAnswer.stages ?? []).length > 0
			? {
					reconciles: scheduleAnswer.reconciles ?? null,
					job_total_minor: scheduleAnswer.job_total_minor ?? null,
					stages: scheduleAnswer.stages
				}
			: null;

	return json(
		{
			recurrence,
			schedule,
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
			reminders,
			organization_today: organizationToday,
			money,
			costing,
			locale: formatting.ok ? formatting.formatting.locale : 'en-US',
			can_edit: canEdit,
			can_schedule: canSchedule,
			can_complete: canComplete,
			can_close: canClose,
			can_see_price: canSeePrice,
			can_see_cost: canSeeCost,
			can_manage_taxes: canManageTaxes,
			can_invoice: canInvoice,
			// Whether `invoiced` on each visit is trustworthy. False collapses to "nothing billed yet" above,
			// which the visits-to-bill card must not show as fact without this — so it gates on this flag too.
			can_invoice_visits: canSeeInvoiceStatus
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
