import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { experienceDecisionSchema, zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';
import {
	loadExperienceDecisions,
	orderDecisionChain,
	resolveExperienceProfile
} from '$lib/server/experience/profile';
import type { ExperienceTabResponse } from '$lib/experience/types';

// Multi-industry foundation B1: the Organization's Industry experience profile and its decision history.
// Anyone who may open Organizations can read it; recording a decision is the Platform Owner's
// (`OWNER_ONLY_CHANGES`). The answer names experiences, Business types and Agreements so the Control Room
// can show the history without further requests.

async function loadExperienceTab(organizationId: string): Promise<ExperienceTabResponse> {
	const client = getOwnerSupabaseClient();
	const [decisions, definitions, businessTypes, currentAgreement] = await Promise.all([
		loadExperienceDecisions(client, organizationId),
		client
			.from('industry_experience_definitions')
			.select('experience_key, version, name, status, capability_families, published_at'),
		client
			.from('industry_experience_business_types')
			.select('experience_key, definition_version, business_type_key, label, position')
			.order('position'),
		client
			.from('organization_package_agreements')
			.select('id')
			.eq('organization_id', organizationId)
			.is('cancelled_at', null)
			.lte('effective_from', new Date().toISOString())
			.order('effective_from', { ascending: false })
			.order('created_at', { ascending: false })
			.limit(1)
			.maybeSingle()
	]);
	if (definitions.error) throw definitions.error;
	if (businessTypes.error) throw businessTypes.error;
	if (currentAgreement.error) throw currentAgreement.error;

	const agreementIds = [
		...new Set(
			[
				currentAgreement.data?.id,
				...decisions.map((decision) => decision.package_agreement_id)
			].filter((id): id is string => Boolean(id))
		)
	];
	const agreements = agreementIds.length
		? await client
				.from('organization_package_agreements')
				.select('id, effective_from, package_editions(name)')
				.in('id', agreementIds)
		: { data: [], error: null };
	if (agreements.error) throw agreements.error;
	const agreementById = new Map(
		agreements.data.map((agreement) => [
			agreement.id,
			{
				id: agreement.id,
				package_name: agreement.package_editions?.name ?? 'Unknown package',
				effective_from: agreement.effective_from
			}
		])
	);

	const definitionName = (key: string, version: number) =>
		definitions.data.find((d) => d.experience_key === key && d.version === version)?.name ?? null;
	const businessTypeLabel = (key: string, version: number, type: string | null) =>
		type
			? (businessTypes.data.find(
					(t) =>
						t.experience_key === key &&
						t.definition_version === version &&
						t.business_type_key === type
				)?.label ?? null)
			: null;

	const profile = resolveExperienceProfile(decisions);
	const history = (orderDecisionChain(decisions) ?? decisions).map((decision) => ({
		...decision,
		experience_name: definitionName(decision.experience_key, decision.definition_version),
		business_type_label: businessTypeLabel(
			decision.experience_key,
			decision.definition_version,
			decision.business_type_key
		),
		agreement: decision.package_agreement_id
			? (agreementById.get(decision.package_agreement_id) ?? null)
			: null
	}));

	return {
		profile: {
			state: profile.state,
			experience: profile.experience,
			decision_id: profile.decision?.id ?? null
		},
		history,
		// Only published definitions can be confirmed; a draft or retired one is never offered.
		definitions: definitions.data
			.filter((definition) => definition.status === 'published')
			.map((definition) => ({
				experience_key: definition.experience_key,
				version: definition.version,
				name: definition.name,
				capability_families: definition.capability_families,
				business_types: businessTypes.data
					.filter(
						(type) =>
							type.experience_key === definition.experience_key &&
							type.definition_version === definition.version
					)
					.map((type) => ({ key: type.business_type_key, label: type.label }))
			})),
		current_agreement: currentAgreement.data
			? (agreementById.get(currentAgreement.data.id) ?? null)
			: null
	};
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	try {
		return json(await loadExperienceTab(parsedId.data), {
			headers: { 'cache-control': 'no-store' }
		});
	} catch (error) {
		console.error('Could not load the experience profile.', error);
		return json({ error: 'The experience profile could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const parsedId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedId.success)
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = experienceDecisionSchema.safeParse(body);
	if (!parsed.success)
		return json(
			{ error: 'Please review the decision.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);

	try {
		const command = parsed.data;
		const { data, error } = await getOwnerSupabaseClient().rpc(
			'record_organization_experience_decision',
			{
				target_organization_id: parsedId.data,
				target_experience_key: command.experience_key,
				target_definition_version: command.definition_version,
				// The command keeps a null Business type as "not yet confirmed"; the generated type omits null.
				target_business_type_key: command.business_type_key as string,
				reviewed_service_shape: command.service_shape,
				decision_reason: command.reason,
				expected_previous_decision_id: command.expected_previous_decision_id as string,
				idempotency_key: command.idempotency_key,
				actor_email: session.email
			}
		);
		if (error) {
			if (error.code === '23503' && error.message.startsWith('Organization was not found'))
				return json({ error: 'Organization was not found.' }, { status: 404 });
			if (['23503', '23505', '23514', 'P0409'].includes(error.code ?? ''))
				return json({ error: error.message }, { status: 409 });
			throw error;
		}

		return json(
			{ command: data, ...(await loadExperienceTab(parsedId.data)) },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not record the experience decision.', error);
		return json({ error: 'The experience decision could not be recorded.' }, { status: 500 });
	}
};
