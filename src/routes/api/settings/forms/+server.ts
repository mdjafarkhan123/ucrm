import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { formReadError, formWriteError } from '$lib/server/forms/errors';
import { formCreateSchema } from '$lib/server/validation/forms.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { FormListItem, FormOutcome } from '$lib/forms/types';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

// Same slugify + collision-suffix convention as organization provisioning (see
// api/jafar/prospects/[prospectId]/provision) -- a readable, stable public address, generated once here
// and never regenerated automatically even if the form is later renamed.
function slugify(name: string) {
	return (
		name
			.toLowerCase()
			.replace(/[^a-z0-9]+/g, '-')
			.replace(/^-+|-+$/g, '')
			.slice(0, 80) || 'form'
	);
}

type VersionRow = { id: string; version_number: number; status: string; title: string };
type FormRow = {
	id: string;
	outcome: FormOutcome;
	name: string;
	is_enabled: boolean;
	is_default: boolean;
	archived_at: string | null;
	revision: number;
	draft_version_id: string | null;
	current_published_version_id: string | null;
	form_versions: VersionRow[];
};

// The list of a business's request/booking forms. Only a form manager may see it — the RLS policy enforces
// that too, but the guard turns "not allowed" into an honest answer instead of an empty list.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const includeArchived = event.url.searchParams.get('archived') === 'true';

	let query = event.locals.supabase
		.from('forms')
		.select(
			'id,outcome,name,is_enabled,is_default,archived_at,revision,draft_version_id,current_published_version_id,form_versions!form_versions_form_organization_fk(id,version_number,status,title)'
		)
		.eq('organization_id', check.auth.organization.id)
		.order('name', { ascending: true });

	if (!includeArchived) query = query.is('archived_at', null);

	const { data, error } = await query;
	if (error) return formReadError(error);

	const items: FormListItem[] = ((data as FormRow[]) ?? []).map((form) => {
		const published = form.form_versions.find((v) => v.id === form.current_published_version_id);
		const draft = form.form_versions.find((v) => v.id === form.draft_version_id);
		return {
			id: form.id,
			outcome: form.outcome,
			name: form.name,
			is_enabled: form.is_enabled,
			is_default: form.is_default,
			archived_at: form.archived_at,
			revision: form.revision,
			has_draft: form.draft_version_id !== null,
			published_version_number: published?.version_number ?? null,
			title: published?.title ?? draft?.title ?? form.name
		};
	});

	return json(items, { headers: PRIVATE_READ_HEADERS });
};

// Create a new form. It starts as a Draft (version 1) seeded with a usable default builder; the command
// picks the outcome and both customer-facing title and internal name.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-forms-create:${organizationId}`,
			...SAVE_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = formCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const baseSlug = slugify(parsed.data.title);
	const { data: existingSlugs, error: slugError } = await event.locals.supabase
		.from('forms')
		.select('public_slug')
		.eq('organization_id', organizationId)
		.ilike('public_slug', `${baseSlug}%`);
	if (slugError) return databaseError();
	const takenSlugs = new Set((existingSlugs ?? []).map((row) => row.public_slug));
	let publicSlug = baseSlug;
	let suffix = 2;
	while (takenSlugs.has(publicSlug)) publicSlug = `${baseSlug}-${suffix++}`;

	const { data, error } = await event.locals.supabase.rpc('create_form', {
		target_organization_id: organizationId,
		new_outcome: parsed.data.outcome,
		new_name: parsed.data.name,
		new_public_slug: publicSlug,
		new_title: parsed.data.title,
		new_description: parsed.data.description ? parsed.data.description : null
	});

	if (error) return formWriteError(error);
	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
