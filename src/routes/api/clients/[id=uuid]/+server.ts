import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { ClientWorkSummary } from '$lib/clients/api';
import { requireClientPermission } from '$lib/server/access/clients';
import { hasPermission, permissionScope } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { databaseError, validationError } from '$lib/server/api/errors';
import {
	clientWriteSchema,
	deriveClientDisplayName,
	zodFieldErrors
} from '$lib/server/validation/foundation.schema';
import {
	duplicateResponse,
	findExactDuplicates,
	readWriteFailure
} from '$lib/server/clients/duplicates';

const NOT_FOUND = { error: 'That client could not be found.' };

// Everything the create/edit form and the detail page need, in one request. The form reads the primary
// property; the detail page lists them all. Tags, notes, and attachments stay with the collaboration API,
// since their cards already own that data and write to it.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.view');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const clientId = event.params.id;
	const supabase = event.locals.supabase;

	const { data: client, error } = await supabase
		.from('clients')
		.select(
			'id, display_name, client_type, first_name, last_name, company_name, lifecycle_status, lead_source, lead_temperature, next_follow_up_at, converted_to_customer_at, archived_at, created_at, updated_at'
		)
		.eq('organization_id', organizationId)
		.eq('id', clientId)
		.is('deleted_at', null)
		.maybeSingle();
	if (error) return databaseError();
	if (!client) {
		// A client merged into another is gone, but an old link to it (a bookmark, an email, a teammate's
		// open tab) should land on the client it became rather than a dead end.
		const { data: survivorId } = await supabase.rpc('resolve_merged_client', {
			p_client_id: clientId
		});
		return json(survivorId ? { ...NOT_FOUND, merged_into: survivorId } : NOT_FOUND, {
			status: 404
		});
	}

	const [
		{ data: contactMethods, error: contactMethodsError },
		{ data: properties, error: propertiesError },
		{ data: preferences, error: preferencesError },
		{ data: tagAssignments, error: tagAssignmentsError },
		{ data: workSummary, error: workSummaryError }
	] = await Promise.all([
		supabase
			.from('client_contact_methods')
			.select('id, kind, value, is_primary, is_billing_contact')
			.eq('organization_id', organizationId)
			.eq('client_id', clientId),
		supabase
			.from('properties')
			.select(
				'id, label, address_line1, address_line2, city, state_region, postal_code, country, access_notes, is_primary, is_billing_address, tax_rate_id'
			)
			.eq('organization_id', organizationId)
			.eq('client_id', clientId)
			.is('deleted_at', null),
		supabase
			.from('client_communication_preferences')
			.select(
				'contact_policy, quote_follow_ups, invoice_reminders, appointment_reminders, job_follow_ups, review_requests, sms_opt_out_at, sms_opt_in_at'
			)
			.eq('organization_id', organizationId)
			.eq('client_id', clientId)
			.maybeSingle(),
		supabase
			.from('tag_assignments')
			.select('tag_id')
			.eq('organization_id', organizationId)
			.eq('entity_type', 'client')
			.eq('entity_id', clientId),
		supabase.rpc('client_work_summary', { target_client_ids: [clientId] })
	]);
	if (
		contactMethodsError ||
		propertiesError ||
		preferencesError ||
		tagAssignmentsError ||
		workSummaryError
	)
		return databaseError();

	const primaryOf = (kind: 'email' | 'phone') =>
		(contactMethods ?? []).find((method) => method.kind === kind && method.is_primary)?.value ??
		null;

	const billingEmail =
		(contactMethods ?? []).find((method) => method.kind === 'email' && method.is_billing_contact)
			?.value ?? null;

	// Marketing-email consent is tracked per email method in a service-role-only evidence ledger, so it is
	// read here with the owner client rather than the request's RLS-scoped one. Only the primary email is
	// surfaced: it is the address marketing would send to, and staff record against one email, not in bulk.
	const primaryEmailMethod =
		(contactMethods ?? []).find((method) => method.kind === 'email' && method.is_primary) ??
		(contactMethods ?? []).find((method) => method.kind === 'email') ??
		null;

	let marketingConsent: {
		email: string;
		contact_method_id: string;
		state: 'opted_in' | 'opted_out' | 'unknown';
		source: string | null;
		effective_at: string | null;
	} | null = null;

	if (primaryEmailMethod) {
		const owner = getOwnerSupabaseClient();
		const { data: consentRow, error: consentError } = await owner
			.from('client_marketing_consent_state')
			.select('state, effective_at, source_event_id')
			.eq('organization_id', organizationId)
			.eq('client_contact_method_id', primaryEmailMethod.id)
			.maybeSingle();
		if (consentError) return databaseError();

		let source: string | null = null;
		if (consentRow) {
			const { data: sourceEvent, error: sourceError } = await owner
				.from('client_marketing_consent_events')
				.select('source')
				.eq('organization_id', organizationId)
				.eq('id', consentRow.source_event_id)
				.maybeSingle();
			if (sourceError) return databaseError();
			source = sourceEvent?.source ?? null;
		}

		marketingConsent = {
			email: primaryEmailMethod.value,
			contact_method_id: primaryEmailMethod.id,
			state: (consentRow?.state as 'opted_in' | 'opted_out' | undefined) ?? 'unknown',
			source,
			effective_at: consentRow?.effective_at ?? null
		};
	}

	const workSummaryRow = (
		(workSummary ?? {}) as Record<string, Omit<ClientWorkSummary, 'included'>>
	)[clientId] ?? {
		currency_code: 'USD',
		lifetime_billed_minor: null,
		open_quotes_count: null,
		active_jobs_count: null
	};

	return json({
		client: {
			...client,
			contact_methods: contactMethods ?? [],
			email: primaryOf('email'),
			billing_email: billingEmail,
			phone: primaryOf('phone'),
			primary_property:
				(properties ?? []).find((property) => property.is_primary) ?? properties?.[0] ?? null,
			// Primary first, then the rest in a stable order, so the detail page's address list reads the
			// way the office thinks about it.
			properties: [...(properties ?? [])].sort((left, right) =>
				left.is_primary === right.is_primary
					? left.address_line1.localeCompare(right.address_line1)
					: left.is_primary
						? -1
						: 1
			),
			property_count: (properties ?? []).length,
			preferences,
			marketing_consent: marketingConsent,
			tag_ids: (tagAssignments ?? []).map((assignment) => assignment.tag_id),
			// Google review Part 3. A member limited to their own jobs asks from the job page instead, since
			// the client page may offer a job they did not work on or no job at all.
			can_request_review: permissionScope(access.access, 'reviews.request') === 'all',
			// Whether this member may archive or restore this client, so the header shows the action only to
			// someone the archive route would actually let through.
			can_archive: hasPermission(access.access, 'customers.archive'),
			// Whether this member may merge another client into this one (customers.merge).
			can_merge: hasPermission(access.access, 'customers.merge'),
			// A tile whose feature the package leaves out is not shown at all, rather than reading as a refusal.
			work_summary: {
				...workSummaryRow,
				included: {
					billing: access.access.features['core.invoices_payments'] === true,
					quotes: access.access.features['core.quotes'] === true,
					jobs: access.access.features['core.jobs'] === true
				}
			}
		}
	});
};

export const PATCH: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.edit');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = clientWriteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;
	const clientId = event.params.id;

	// The client being edited never counts as its own duplicate.
	const duplicates = await findExactDuplicates(event.locals.supabase, organizationId, {
		...parsed.data,
		excludeClientId: clientId
	});
	if ('failed' in duplicates) return databaseError();
	if (duplicates.matches.length > 0) return duplicateResponse(duplicates.matches);

	const { data, error } = await event.locals.supabase.rpc('update_client', {
		payload: {
			organization_id: organizationId,
			id: clientId,
			display_name: deriveClientDisplayName(parsed.data),
			...parsed.data
		}
	});

	if (error) {
		const failure = readWriteFailure(error);
		if (failure.kind === 'not_found') return json(NOT_FOUND, { status: 404 });
		if (failure.kind === 'duplicate') {
			const raced = await findExactDuplicates(event.locals.supabase, organizationId, {
				...parsed.data,
				excludeClientId: clientId
			});
			if ('failed' in raced) return databaseError();
			return duplicateResponse(raced.matches, failure.field);
		}
		// A customer cannot be turned back into a lead; the database says so and the office should see why.
		if (failure.kind === 'rule')
			return json({ error: failure.message, field_errors: {} }, { status: 422 });
		return databaseError();
	}

	return json({ client: data });
};
