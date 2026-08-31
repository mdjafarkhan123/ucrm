import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { validateDefinition } from '$lib/server/automation/definition';
import { definitionLimits, commandErrorResponse } from '$lib/server/automation/commands';
import {
	createRecipeDraftSchema,
	automationFieldErrors
} from '$lib/server/validation/automation-authoring.schema';

// Settings → Automation home: the recipe list. Read-only, cursor-paginated, tenant-scoped by RLS on top of
// the requireAutomationAccess('view') gate. Projects summaries only — never definitions, so the payload
// stays small (docs/automation-behavior-contract.md § Query, index, and count). Status counts for the
// overview cards/strip are bounded indexed queries returned only on the first page.

const PAGE_SIZE = 25;

const STATUSES = ['active', 'paused', 'draft', 'archived'] as const;
type RecipeStatus = (typeof STATUSES)[number];

function readCursor(raw: string | null) {
	if (!raw) return null;
	const separator = raw.lastIndexOf('|');
	if (separator < 1) return null;
	const value = raw.slice(0, separator);
	const id = raw.slice(separator + 1);
	if (id.length === 0) return null;
	return { value, id };
}

function quoteFilterValue(value: string) {
	return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

type RecipeRow = {
	id: string;
	name: string;
	status: RecipeStatus;
	source: 'preset' | 'custom';
	active_trigger_key: string | null;
	draft_trigger_key: string | null;
	updated_at: string;
};

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;
	const params = event.url.searchParams;

	const statusParam = params.get('status');
	const status = STATUSES.includes(statusParam as RecipeStatus)
		? (statusParam as RecipeStatus)
		: null;
	const sourceParam = params.get('source');
	const source = sourceParam === 'preset' || sourceParam === 'custom' ? sourceParam : null;
	const search = params.get('search')?.trim() ?? '';
	const cursor = readCursor(params.get('cursor'));

	let query = supabase
		.from('automation_recipes')
		.select(
			'id, name, status, source, active_trigger_key, updated_at, draft_trigger_key:draft_definition->trigger->>key'
		)
		.eq('organization_id', organizationId);

	if (status) query = query.eq('status', status);
	if (source) query = query.eq('source', source);
	if (search) {
		const escaped = search.replace(/[\\%_]/g, (match) => `\\${match}`);
		query = query.ilike('name', `%${escaped}%`);
	}
	if (cursor) {
		// Keyset seek for (updated_at desc, id desc): start at the cursor row, then drop it and its ties.
		const quoted = quoteFilterValue(cursor.value);
		query = query
			.lte('updated_at', cursor.value)
			.or(`updated_at.lt.${quoted},and(updated_at.eq.${quoted},id.lt.${cursor.id})`);
	}

	const { data, error } = await query
		.order('updated_at', { ascending: false })
		.order('id', { ascending: false })
		.limit(PAGE_SIZE + 1);
	if (error) return databaseError();

	const rows = (data ?? []) as unknown as RecipeRow[];
	const page = rows.slice(0, PAGE_SIZE);
	const hasMore = rows.length > PAGE_SIZE;
	const last = page.at(-1);
	const nextCursor = hasMore && last ? `${last.updated_at}|${last.id}` : null;

	// Active-enrollment counts for exactly this page's recipes: one bounded, indexed grouped query through
	// the security-definer projection (docs/automation-behavior-contract.md § Query, index, and count). The
	// engine tables live in `private`, so this goes through the service client; a recipe with no active
	// enrollment is simply absent from the result and reads as zero.
	const activeById = new Map<string, number>();
	if (page.length > 0) {
		const { data: countRows, error: countError } = await getOwnerSupabaseClient().rpc(
			'automation_active_enrollment_counts',
			{ p_organization_id: organizationId, p_recipe_ids: page.map((row) => row.id) }
		);
		if (countError) return databaseError();
		for (const row of (countRows ?? []) as { recipe_id: string; active_count: number }[]) {
			activeById.set(row.recipe_id, Number(row.active_count));
		}
	}

	const recipes = page.map((row) => ({
		id: row.id,
		name: row.name,
		status: row.status,
		source: row.source,
		// Live matching uses the active version's trigger; a never-activated draft shows its draft trigger.
		trigger_key: row.active_trigger_key ?? row.draft_trigger_key ?? null,
		active_enrollments: activeById.get(row.id) ?? 0,
		last_activity_at: row.updated_at
	}));

	// Counts drive the overview cards and the active-recipe strip; they are page-level, so compute them once
	// on the first page (no cursor) and let the client keep them while paging.
	let counts: { active: number; paused: number; draft: number } | null = null;
	if (!cursor) {
		const countFor = (value: RecipeStatus) =>
			supabase
				.from('automation_recipes')
				.select('id', { count: 'exact', head: true })
				.eq('organization_id', organizationId)
				.eq('status', value);
		const [active, paused, draft] = await Promise.all([
			countFor('active'),
			countFor('paused'),
			countFor('draft')
		]);
		if (active.error || paused.error || draft.error) return databaseError();
		counts = {
			active: active.count ?? 0,
			paused: paused.count ?? 0,
			draft: draft.count ?? 0
		};
	}

	return json({ recipes, counts, next_cursor: nextCursor }, { headers: PRIVATE_READ_HEADERS });
};

type DraftCommandResult = { recipe_id: string; draft_revision: number };

// Create a new recipe as a draft. `manage` is required; the definition is validated against the same catalog
// the builder uses, any referenced email templates must belong to this organization, and the atomic command
// enforces organization ownership and idempotency so a retried submit never creates a second recipe.
export const POST: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'manage');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = createRecipeDraftSchema.safeParse(body);
	if (!parsed.success) return validationError(automationFieldErrors(parsed.error));

	const validated = validateDefinition(
		parsed.data.definition,
		definitionLimits(check.automation),
		'draft'
	);
	if (!validated.ok) {
		return validationError(
			Object.fromEntries(
				validated.errors.map((issue) => [`definition.${issue.path}`, issue.message])
			)
		);
	}

	const organizationId = check.auth.organization.id;
	const service = getOwnerSupabaseClient();

	try {
		const { data, error } = await service.rpc('create_automation_recipe_draft', {
			p_organization_id: organizationId,
			p_actor_user_id: check.auth.user.id,
			p_name: parsed.data.name,
			p_source: parsed.data.source,
			p_preset_key: parsed.data.source === 'preset' ? (parsed.data.preset_key ?? null) : null,
			p_preset_version:
				parsed.data.source === 'preset' ? (parsed.data.preset_version ?? null) : null,
			p_definition: JSON.parse(validated.definitionJson),
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;
		const result = data as unknown as DraftCommandResult;
		return json(
			{ recipe_id: result.recipe_id, draft_revision: result.draft_revision },
			{ status: 201 }
		);
	} catch (error) {
		return commandErrorResponse(error, 'We could not create that automation. Please try again.');
	}
};
