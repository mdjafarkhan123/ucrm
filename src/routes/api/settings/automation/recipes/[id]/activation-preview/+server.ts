import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { validateDefinition } from '$lib/server/automation/definition';
import { definitionLimits, activeRecipesLimit } from '$lib/server/automation/commands';
import { triggerLabel } from '$lib/automation/catalog';

// Settings → Automation: the impact preview the activation dialog reads when it opens. `activate` is required
// — only someone who could actually activate needs to see the impact. It reads the recipe's OWN saved draft,
// revalidates it at activation strictness and re-checks referenced email templates, and reports the effective
// limits and active-recipe headroom, so the dialog can present the impact and block Activate without the
// browser reconstructing entitlement (docs/automation-behavior-contract.md § Activation impact review). This
// is a read: it never freezes anything. Confirm re-runs the same checks in the atomic command.

const recipeIdSchema = z.string().uuid();

type DraftRow = {
	status: string;
	draft_definition: unknown;
	draft_revision: number;
};

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'activate');
	if ('response' in check) return check.response;

	const recipeId = recipeIdSchema.safeParse(event.params.id);
	if (!recipeId.success) return json({ error: 'That automation does not exist.' }, { status: 404 });

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	const { data: recipe, error } = await supabase
		.from('automation_recipes')
		.select('status, draft_definition, draft_revision')
		.eq('organization_id', organizationId)
		.eq('id', recipeId.data)
		.maybeSingle<DraftRow>();
	if (error) return databaseError();
	if (!recipe) return json({ error: 'That automation does not exist.' }, { status: 404 });

	// How many recipes are already live, and the ceiling. Activation — not save — enforces this; an
	// already-active recipe keeps its slot on re-activation, so it is never counted as over the limit.
	const { count, error: countError } = await supabase
		.from('automation_recipes')
		.select('id', { count: 'exact', head: true })
		.eq('organization_id', organizationId)
		.eq('status', 'active');
	if (countError) return databaseError();
	const activeCount = count ?? 0;
	const limit = activeRecipesLimit(check.automation);
	const alreadyActive = recipe.status === 'active';
	const overLimit = limit !== null && !alreadyActive && activeCount >= limit;

	// Structural + template revalidation at activation strictness (>=1 step, >=1 stop), against the same
	// catalog and limits the builder and the atomic command use. Blocking findings are surfaced in plain text.
	const blocking: string[] = [];
	let summary: {
		trigger_label: string;
		max_messages: number;
		step_count: number;
		condition_count: number;
		stop_count: number;
	} | null = null;

	if (recipe.status === 'archived') {
		blocking.push('This automation is archived and cannot be activated.');
	} else if (recipe.draft_definition == null) {
		blocking.push('This automation has no saved draft to activate.');
	} else {
		const validated = validateDefinition(
			recipe.draft_definition,
			definitionLimits(check.automation),
			'activation'
		);
		if (!validated.ok) {
			for (const issue of validated.errors) blocking.push(issue.message);
		} else {
			summary = {
				trigger_label: triggerLabel(validated.triggerKey),
				max_messages: validated.definition.steps.filter((step) => step.key === 'action.send_email')
					.length,
				step_count: validated.definition.steps.length,
				condition_count: validated.definition.conditions.length,
				stop_count: validated.definition.stops.length
			};
		}
	}

	return json(
		{
			recipe_id: recipeId.data,
			status: recipe.status,
			draft_revision: recipe.draft_revision,
			already_active: alreadyActive,
			valid: blocking.length === 0 && !overLimit,
			blocking,
			summary,
			active_recipes: {
				limit,
				count: activeCount,
				over_limit: overLimit
			},
			effective_limits: {
				automation_max_customer_messages_per_enrollment:
					check.automation.limits.automation_max_customer_messages_per_enrollment,
				automation_min_customer_message_spacing_minutes:
					check.automation.limits.automation_min_customer_message_spacing_minutes,
				automation_max_delay_days: check.automation.limits.automation_max_delay_days,
				automation_max_enrollment_duration_days:
					check.automation.limits.automation_max_enrollment_duration_days
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
