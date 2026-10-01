import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { boardSummaryQuerySchema } from '$lib/server/validation/pipeline.schema';
import {
	ASSESSMENT_GROUP,
	ASSESSMENT_GROUP_STAGES,
	BOARD_STAGES,
	QUOTE_BOARD_STAGES,
	type AnyBoardStage,
	type CustomStage
} from '$lib/pipeline/stages';
import { resolveDateRange, type BoardDateRange } from '$lib/server/pipeline/board';
import { organizationFormatting, type OrganizationFormatting } from '$lib/server/requests/timezone';
import { pipelinePresentation } from '$lib/server/pipeline/presentation';
import { enabledCustomStages } from '$lib/server/pipeline/stages';

// Both groups' columns, in the fixed order their headings need to add up in. Request stages first, matching
// the board's own left-to-right group order.
const ALL_BOARD_STAGES: readonly AnyBoardStage[] = [...BOARD_STAGES, ...QUOTE_BOARD_STAGES];

// Everything the board shows above its cards: the number on every column heading, the money in every
// column heading, and how many cards the whole board is showing. One grouped query for all of it, never
// one count per column — four counts on every board load is the kind of thing that only hurts once the
// boards are busy. The database groups; this route only fills in a zero for a stage that had no rows.
//
// It takes the same salesperson and date filters the columns take, because a heading that counts the
// whole board above a column showing eleven filtered cards is simply wrong. Both sides turn the date
// preset into the same two instants in the organization's own timezone, so they cannot drift apart.
//
// Money is guarded the way the cards guard it: the totals are left out of the payload entirely for a
// member without pricing access, so there is nothing to leak and nothing to misread. `can_view_value`
// says which of those two worlds this member is in — a column with no total in it is otherwise
// indistinguishable from a column nobody has estimated yet.
//
// Cached under its own key in the browser, so a column loading its next page does not re-count the
// board, and a Request, Assessment, or Opportunity change refreshes the numbers on their own.
type StageCountRow = { stage_key: string; open_count: number; value_total: number | null };

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'pipeline.view');
	if ('response' in check) return check.response;

	const query = event.url.searchParams;
	const parsed = boardSummaryQuerySchema.safeParse({
		owner: query.get('owner') ?? undefined,
		date: query.get('date') ?? undefined,
		from: query.get('from') ?? undefined,
		to: query.get('to') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { owner, date } = parsed.data;
	const canViewValue = hasPermission(check.access, 'pipeline.view_value');
	const canEdit = hasPermission(check.access, 'pipeline.edit');

	// The organization's own way of writing money and dates is needed either way — for the currency the
	// totals are shown in, and for the calendar a date filter is measured against. The settings row is
	// held in process for a few minutes, so this is usually free.
	const formattingRead = organizationFormatting(check.auth.organization.id);

	// Which board this organization is showing. It rides along with the headings because this is the query
	// the board already holds and already invalidates — saving the toggle refreshes the numbers and the
	// shape together, so the board never has to be told twice or reloaded by hand.
	const presentationRead = pipelinePresentation(check.auth.organization.id);

	// The custom columns ride along for the same reason: adding, renaming, or moving a stage in Settings
	// refreshes this one query and the board redraws. Their numbers come back from the same grouped count
	// as the protected ones, under the stage's id.
	const stagesRead = enabledCustomStages(event.locals.supabase, check.auth.organization.id);

	const countBetween = (range: BoardDateRange) =>
		event.locals.supabase.rpc('pipeline_stage_counts', {
			target_organization_id: check.auth.organization.id,
			owner_filter: owner === 'all' || owner === 'unassigned' ? owner : 'member',
			filter_owner_user_id: owner === 'all' || owner === 'unassigned' ? undefined : owner,
			created_from: range.from ?? undefined,
			created_to: range.to ?? undefined
		});

	// A date filter has to become two instants before the counting query can be asked, so those two reads
	// run one after the other. Without one — which is how the board opens — they are independent, so they
	// go together and the board never waits for a calendar it is not using.
	if (date === 'all') {
		const [formattingLookup, presentationLookup, stagesLookup, counted] = await Promise.all([
			formattingRead,
			presentationRead,
			stagesRead,
			countBetween({ from: null, to: null })
		]);
		if (!formattingLookup.ok || !presentationLookup.ok || !stagesLookup.ok || counted.error)
			return databaseError();
		return summary(
			formattingLookup.formatting,
			presentationLookup.presentation.detailed_assessment_stages,
			stagesLookup.stages,
			counted.data,
			canViewValue,
			canEdit
		);
	}

	const [formattingLookup, presentationLookup, stagesLookup] = await Promise.all([
		formattingRead,
		presentationRead,
		stagesRead
	]);
	// A settings row that could not be read is a failure, not a reason to quietly show the wrong currency,
	// the wrong calendar day, or the wrong board.
	if (!formattingLookup.ok || !presentationLookup.ok || !stagesLookup.ok) return databaseError();

	const counted = await countBetween(
		resolveDateRange(date, formattingLookup.formatting.timezone, {
			from: parsed.data.from,
			to: parsed.data.to
		})
	);
	if (counted.error) return databaseError();
	return summary(
		formattingLookup.formatting,
		presentationLookup.presentation.detailed_assessment_stages,
		stagesLookup.stages,
		counted.data,
		canViewValue,
		canEdit
	);
};

function summary(
	formatting: OrganizationFormatting,
	detailedAssessmentStages: boolean,
	customStages: CustomStage[],
	rows: unknown,
	canViewValue: boolean,
	canEdit: boolean
): Response {
	const counts = Object.fromEntries(ALL_BOARD_STAGES.map((stage) => [stage, 0])) as Record<
		AnyBoardStage,
		number
	>;
	// Null stays null: it means nobody has estimated anything in that column, which is not the same
	// answer as zero, and must never be shown as $0.00.
	const valueTotals = Object.fromEntries(ALL_BOARD_STAGES.map((stage) => [stage, null])) as Record<
		AnyBoardStage,
		number | null
	>;

	// A card placed in a custom stage is counted under that stage and not under its real one, so every
	// heading is the number of cards actually drawn beneath it. Only stages the board is being told about
	// get a number: a count for a column nobody can see would be money and cards that add up to nothing.
	const customCounts = Object.fromEntries(customStages.map((stage) => [stage.id, 0])) as Record<
		string,
		number
	>;
	const customValueTotals = Object.fromEntries(
		customStages.map((stage) => [stage.id, null])
	) as Record<string, number | null>;

	for (const row of (rows ?? []) as StageCountRow[]) {
		const total = row.value_total === null ? null : Number(row.value_total);
		if (row.stage_key in counts) {
			counts[row.stage_key as AnyBoardStage] = Number(row.open_count);
			valueTotals[row.stage_key as AnyBoardStage] = total;
		} else if (row.stage_key in customCounts) {
			customCounts[row.stage_key] = Number(row.open_count);
			customValueTotals[row.stage_key] = total;
		}
	}

	// The collapsed column's own heading, added up here rather than in the browser so the number under
	// "Assessment" can never disagree with the three it is made of. Null stays null on the same rule the
	// individual columns follow: three columns nobody has estimated total to "nothing estimated", not $0.
	const groupedCount = ASSESSMENT_GROUP_STAGES.reduce((total, stage) => total + counts[stage], 0);
	const groupedTotals = ASSESSMENT_GROUP_STAGES.map((stage) => valueTotals[stage]).filter(
		(total): total is number => total !== null
	);

	return json(
		{
			counts: {
				...counts,
				[ASSESSMENT_GROUP]: groupedCount
			},
			// The control bar's "showing N" line, both groups combined -- Jobber's own board shows one
			// number for the whole board, not one per group. Added up from the same numbers the headings
			// show rather than counted again, so it can never disagree with them.
			result_count:
				ALL_BOARD_STAGES.reduce((total, stage) => total + counts[stage], 0) +
				Object.values(customCounts).reduce((total, count) => total + count, 0),
			// Each custom column's own heading, by stage id.
			custom_counts: customCounts,
			// Present only for a member who may see money. Absent, not null, for everyone else.
			...(canViewValue
				? {
						value_totals: {
							...valueTotals,
							[ASSESSMENT_GROUP]:
								groupedTotals.length === 0
									? null
									: groupedTotals.reduce((total, value) => total + value, 0)
						},
						// Each custom column's money, by stage id. Null on the same rule as above.
						custom_value_totals: customValueTotals
					}
				: {}),
			// Whether money exists for this member at all. The board asks once, here, instead of guessing
			// from whether a card happened to carry a value — a column of blank estimates is not the same
			// answer as no permission to see them.
			can_view_value: canViewValue,
			// Whether this member may assign, reassign, or clear a card's owner. The board asks once, here,
			// rather than every card guessing from whether it happens to have an owner already.
			can_edit: canEdit,
			// Which board to draw: false is the five-column default with one Assessment column, true is the
			// seven-column detailed view. Presentation only — the counts above are the same either way.
			detailed_assessment_stages: detailedAssessmentStages,
			// The organization's custom follow-up columns, in saved order. Each names its section and the
			// protected stage it sits after; the board places them from that.
			custom_stages: customStages,
			// Money and dates are written the organization's way, not the browser's.
			currency_code: formatting.currency_code,
			locale: formatting.locale,
			timezone: formatting.timezone
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
}
