import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';
import { loadPaperworkForm } from '$lib/server/communications/sms-number-paperwork';
import {
	asJson,
	ensureDocumentRows,
	presentPaperwork,
	readPaperwork
} from '$lib/server/communications/sms-number-paperwork-api';
import {
	paperworkFieldErrors,
	paperworkSaveSchema
} from '$lib/server/validation/communications-sms-paperwork.schema';

const notFound = () =>
	json({ error: 'That paperwork was not found.' }, { status: 404, headers: NO_STORE_HEADERS });
const unreachable = () =>
	json(
		{
			error:
				'We couldn’t reach the phone company to read what this country asks for. Try again in a minute.'
		},
		{ status: 503, headers: NO_STORE_HEADERS }
	);

async function authorize(event: Parameters<RequestHandler>[0]) {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check;
	const id = z.uuid().safeParse(event.params.paperworkId);
	return { ...check, paperworkId: id.success ? id.data : null };
}

async function formFor(paperwork: {
	countryCode: string;
	numberType: string;
	endUserType: string;
}) {
	return (
		await loadPaperworkForm(getSmsCountryCatalog(), {
			countryCode: paperwork.countryCode,
			numberType: paperwork.numberType as 'local',
			endUserType: paperwork.endUserType as 'business'
		})
	).form;
}

// One set of paperwork with the form its country asks for now, read live from Twilio.
export const GET: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;
	if (!check.paperworkId) return notFound();

	const client = getOwnerSupabaseClient();
	let loaded;
	try {
		loaded = await readPaperwork(client, check.auth.organization.id, check.paperworkId);
	} catch (error) {
		console.error('Could not read the number paperwork.', error);
		return databaseError();
	}
	if (!loaded) return notFound();

	let form;
	try {
		form = await formFor(loaded.paperwork);
	} catch {
		return unreachable();
	}
	try {
		return json(
			{ paperwork: await presentPaperwork(client, loaded, form) },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read the number paperwork.', error);
		return databaseError();
	}
};

// Save what the business typed, as they type. Only a draft or a set needing a fix can change; the revision
// stops two tabs quietly overwriting each other.
export const PATCH: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;
	if (!check.paperworkId) return notFound();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}
	const parsed = paperworkSaveSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the paperwork.', field_errors: paperworkFieldErrors(parsed.error) },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const client = getOwnerSupabaseClient();
	try {
		const current = await readPaperwork(client, organizationId, check.paperworkId);
		if (!current) return notFound();
		const { paperwork } = current;
		if (paperwork.status !== 'draft' && paperwork.status !== 'needs_fix') {
			return json(
				{ error: 'This paperwork is with the phone company and can’t be changed now.' },
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		}
		const changes = parsed.data;
		// Who owns the numbers decides the kind of bundle, so it is settled once Twilio has one.
		const endUserType =
			changes.end_user_type && !paperwork.providerBundleSid
				? changes.end_user_type
				: paperwork.endUserType;

		const { data: updated, error } = await client
			.from('communication_sms_number_paperwork')
			.update({
				end_user_type: endUserType,
				...(changes.answers !== undefined ? { answers: asJson(changes.answers) } : {}),
				...(changes.address !== undefined ? { address: asJson(changes.address) } : {}),
				...(changes.document_choices !== undefined
					? { document_choices: asJson(changes.document_choices) }
					: {}),
				revision: paperwork.revision + 1,
				updated_at: new Date().toISOString()
			})
			.eq('organization_id', organizationId)
			.eq('id', paperwork.id)
			.eq('revision', changes.expected_revision)
			.in('status', ['draft', 'needs_fix'])
			.select('id');
		if (error) throw error;
		if (!updated?.length) {
			return json(
				{
					error: 'This paperwork was changed somewhere else. Reload to see the latest.',
					code: 'stale'
				},
				{ status: 409, headers: NO_STORE_HEADERS }
			);
		}

		for (const document of changes.documents ?? []) {
			const { error: documentError } = await client
				.from('communication_sms_number_paperwork_documents')
				.upsert(
					{
						organization_id: organizationId,
						paperwork_id: paperwork.id,
						document_type: document.document_type,
						fields: asJson(document.fields),
						updated_at: new Date().toISOString()
					},
					{ onConflict: 'paperwork_id,document_type' }
				);
			if (documentError) throw documentError;
		}

		const saved = await readPaperwork(client, organizationId, paperwork.id);
		if (!saved) return notFound();
		let form;
		try {
			form = await formFor(saved.paperwork);
		} catch {
			return unreachable();
		}
		await ensureDocumentRows(client, saved.paperwork, form);
		const reloaded = (await readPaperwork(client, organizationId, paperwork.id)) ?? saved;
		return json(
			{ paperwork: await presentPaperwork(client, reloaded, form) },
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not save the number paperwork.', error);
		return databaseError();
	}
};

// Delete a draft that was never sent. Its files are deleted by the protected-document sweep two days later.
export const DELETE: RequestHandler = async (event) => {
	const check = await authorize(event);
	if ('response' in check) return check.response;
	if (!check.paperworkId) return notFound();

	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_sms_number_paperwork')
		.delete()
		.eq('organization_id', check.auth.organization.id)
		.eq('id', check.paperworkId)
		.eq('status', 'draft')
		.is('provider_bundle_sid', null)
		.is('submitted_at', null)
		.select('id');
	if (error) {
		console.error('Could not delete the paperwork draft.', error);
		return databaseError();
	}
	if (!data?.length) {
		return json(
			{ error: 'Only a draft that was never sent can be deleted.' },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	}
	return new Response(null, { status: 204, headers: NO_STORE_HEADERS });
};
