import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import {
	prefillAddress,
	prefillAnswers,
	resolveDocumentChoices
} from '$lib/communications/number-paperwork';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';
import { loadPaperworkForm } from '$lib/server/communications/sms-number-paperwork';
import {
	asJson,
	ensureDocumentRows,
	listPaperworkSummaries,
	presentPaperwork,
	readPaperwork,
	readRegistrationAnswers,
	reusedDetails
} from '$lib/server/communications/sms-number-paperwork-api';
import {
	paperworkFieldErrors,
	paperworkStartSchema
} from '$lib/server/validation/communications-sms-paperwork.schema';

const unreachable = () =>
	json(
		{
			error:
				'We couldn’t reach the phone company to read what this country asks for. Try again in a minute.'
		},
		{ status: 503, headers: NO_STORE_HEADERS }
	);

// Number paperwork (Stage 10 Part 3): every set this business has, and the registration details it reuses.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const client = getOwnerSupabaseClient();
	try {
		const [paperwork, registration] = await Promise.all([
			listPaperworkSummaries(client, check.auth.organization.id),
			readRegistrationAnswers(client, check.auth.organization.id)
		]);
		return json(
			{ paperwork, reused: reusedDetails(registration) },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not list the number paperwork.', error);
		return databaseError();
	}
};

// Start paperwork for a country and number kind, filled in from the texting registration. A business has one
// set per country and kind, so starting one that exists opens it instead.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}
	const parsed = paperworkStartSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the paperwork.', field_errors: paperworkFieldErrors(parsed.error) },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const client = getOwnerSupabaseClient();
	const query = {
		countryCode: parsed.data.country_code,
		numberType: parsed.data.number_type,
		endUserType: parsed.data.end_user_type
	};

	let form;
	try {
		form = (await loadPaperworkForm(getSmsCountryCatalog(), query)).form;
	} catch {
		return unreachable();
	}

	try {
		const { data: existing, error: existingError } = await client
			.from('communication_sms_number_paperwork')
			.select('id')
			.eq('organization_id', organizationId)
			.eq('country_code', query.countryCode)
			.eq('number_type', query.numberType)
			.maybeSingle();
		if (existingError) throw existingError;

		let id = existing?.id ?? null;
		if (!id) {
			const registration = await readRegistrationAnswers(client, organizationId);
			const answers = prefillAnswers(form, registration);
			const { data: created, error } = await client
				.from('communication_sms_number_paperwork')
				.insert({
					organization_id: organizationId,
					country_code: query.countryCode,
					number_type: query.numberType,
					end_user_type: query.endUserType,
					regulation_sid: form.regulationSid,
					answers: asJson(answers),
					address: asJson(
						form.needsAddress
							? prefillAddress(
									registration,
									answers.business_name ??
										[answers.first_name, answers.last_name].filter(Boolean).join(' ')
								)
							: null
					),
					document_choices: asJson(resolveDocumentChoices(form.requirements, {})),
					created_by: check.auth.user.id
				})
				.select('id')
				.single();
			// Two tabs starting the same set: the second opens the first's.
			if (error?.code === '23505') {
				const { data: raced } = await client
					.from('communication_sms_number_paperwork')
					.select('id')
					.eq('organization_id', organizationId)
					.eq('country_code', query.countryCode)
					.eq('number_type', query.numberType)
					.single();
				id = raced?.id ?? null;
			} else if (error) {
				throw error;
			} else {
				id = created.id;
			}
		}
		if (!id) return databaseError();

		const loaded = await readPaperwork(client, organizationId, id);
		if (!loaded) return databaseError();
		const setForm =
			loaded.paperwork.endUserType === query.endUserType
				? form
				: (
						await loadPaperworkForm(getSmsCountryCatalog(), {
							...query,
							endUserType: loaded.paperwork.endUserType
						})
					).form;
		await ensureDocumentRows(client, loaded.paperwork, setForm);
		const reloaded = (await readPaperwork(client, organizationId, id)) ?? loaded;
		return json(
			{ paperwork: await presentPaperwork(client, reloaded, setForm) },
			{ status: existing ? 200 : 201, headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not start the number paperwork.', error);
		return databaseError();
	}
};
