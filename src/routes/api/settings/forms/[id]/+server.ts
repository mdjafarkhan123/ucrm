import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { formReadError, formWriteError } from '$lib/server/forms/errors';
import { formActionSchema, formDraftSaveSchema } from '$lib/server/validation/forms.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { FormContent, FormDetail, FormOutcome, FormVersionView } from '$lib/forms/types';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 40 };

type VersionRow = {
	id: string;
	version_number: number;
	revision: number;
	title: string;
	description: string | null;
	content: unknown;
	published_at: string | null;
};
type FormRow = {
	id: string;
	outcome: FormOutcome;
	name: string;
	public_slug: string;
	is_enabled: boolean;
	is_default: boolean;
	archived_at: string | null;
	revision: number;
	draft_version_id: string | null;
	current_published_version_id: string | null;
	form_versions: VersionRow[];
};

function toView(row: VersionRow | undefined): FormVersionView | null {
	if (!row) return null;
	return {
		version_id: row.id,
		version_number: row.version_number,
		revision: row.revision,
		title: row.title,
		description: row.description,
		content: row.content as FormContent,
		published_at: row.published_at
	};
}

// One form with its editable draft and/or its current published version, everything the builder needs to
// render, preview, and publish. Reads are RLS-gated to form managers.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('forms')
		.select(
			'id,outcome,name,public_slug,is_enabled,is_default,archived_at,revision,draft_version_id,current_published_version_id,form_versions!form_versions_form_organization_fk(id,version_number,revision,title,description,content,published_at)'
		)
		.eq('organization_id', check.auth.organization.id)
		.eq('id', event.params.id)
		.maybeSingle();

	if (error) return formReadError(error);
	if (!data) return notFound('That form could not be found.');

	const form = data as FormRow;
	const draft = form.form_versions.find((v) => v.id === form.draft_version_id);
	const published = form.form_versions.find((v) => v.id === form.current_published_version_id);

	const detail: FormDetail = {
		id: form.id,
		outcome: form.outcome,
		name: form.name,
		public_slug: form.public_slug,
		is_enabled: form.is_enabled,
		is_default: form.is_default,
		archived_at: form.archived_at,
		revision: form.revision,
		draft: toView(draft),
		published: toView(published)
	};

	return json(detail, { headers: PRIVATE_READ_HEADERS });
};

async function limited(event: Parameters<RequestHandler>[0], organizationId: string) {
	try {
		const limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-forms-write:${organizationId}`,
			...SAVE_LIMIT
		});
		if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);
	} catch {
		return databaseError();
	}
	return null;
}

// Save the whole draft — title, description, and the builder content — under one revision check.
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const rate = await limited(event, organizationId);
	if (rate) return rate;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = formDraftSaveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('update_form_draft', {
		target_organization_id: organizationId,
		target_form_id: event.params.id,
		expected_revision: parsed.data.expected_revision,
		new_title: parsed.data.title,
		new_description: parsed.data.description ? parsed.data.description : null,
		new_content: parsed.data.content
	});

	if (error) return formWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};

// Lifecycle: publish the draft, revise a published form into a fresh draft, set the default, archive/restore,
// or edit the form's name and enabled flag. One action per request, chosen by `action`.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.forms.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const rate = await limited(event, organizationId);
	if (rate) return rate;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = formActionSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const action = parsed.data;
	const formId = event.params.id;
	const supabase = event.locals.supabase;

	const run = () => {
		switch (action.action) {
			case 'publish':
				return supabase.rpc('publish_form_draft', {
					target_organization_id: organizationId,
					target_form_id: formId,
					expected_revision: action.expected_revision
				});
			case 'revise':
				return supabase.rpc('create_form_draft', {
					target_organization_id: organizationId,
					target_form_id: formId
				});
			case 'set_default':
				return supabase.rpc('set_form_default', {
					target_organization_id: organizationId,
					target_form_id: formId,
					expected_revision: action.expected_revision
				});
			case 'archive':
				return supabase.rpc('archive_form', {
					target_organization_id: organizationId,
					target_form_id: formId,
					expected_revision: action.expected_revision
				});
			case 'restore':
				return supabase.rpc('restore_form', {
					target_organization_id: organizationId,
					target_form_id: formId,
					expected_revision: action.expected_revision
				});
			case 'identity':
				return supabase.rpc('update_form_identity', {
					target_organization_id: organizationId,
					target_form_id: formId,
					expected_revision: action.expected_revision,
					new_name: action.name,
					new_is_enabled: action.is_enabled
				});
		}
	};

	const { data, error } = await run();
	if (error) return formWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
