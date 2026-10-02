import type { QuoteDeliveryFailureReason } from '$lib/quotes/send';

// `locals.supabase` is an untyped client, and the generated types for a returns-table function claim
// every column is non-null, which is wrong for this one by design: hidden client details, an unassigned
// owner, and money the caller may not see all come back null. So the row is described here, honestly.
export type BoardPageRow = {
	id: string;
	title: string;
	stage: string;
	stage_entered_at: string;
	outcome: string;
	created_at: string;
	request_id: string | null;
	request_status: string | null;
	client_id: string;
	client_display_name: string | null;
	client_company_name: string | null;
	property_id: string | null;
	property_label: string | null;
	property_address_line1: string | null;
	property_city: string | null;
	property_state_region: string | null;
	property_postal_code: string | null;
	owner_user_id: string | null;
	owner_full_name: string | null;
	owner_avatar_url: string | null;
	estimated_value: number | null;
	expected_close_on: string | null;
	next_task_due_on: string | null;
	task_id: string | null;
	task_title: string | null;
	task_due_on: string | null;
	quote_id: string | null;
	quote_status: string | null;
	assessment_starts_at: string | null;
	assessment_ends_at: string | null;
	custom_stage_id: string | null;
	quote_delivery_failed_at: string | null;
	quote_delivery_failed_email: string | null;
	quote_delivery_failure: QuoteDeliveryFailureReason | null;
	progress_at: string;
	client_lead_source: string | null;
};

// One row of `pipeline_board_page` as the card the board and the Brief draw. Shared by the column read and
// the single-card read, so a Brief opened from a link shows exactly what the board would.
export function toBoardCard(row: BoardPageRow, canViewValue: boolean) {
	return {
		id: row.id,
		title: row.title,
		stage: row.stage,
		// The custom follow-up stage somebody placed this card in, or null when it sits in its real stage.
		// `stage` above is the real one either way.
		custom_stage_id: row.custom_stage_id,
		stage_entered_at: row.stage_entered_at,
		progress_at: row.progress_at,
		outcome: row.outcome,
		created_at: row.created_at,
		expected_close_on: row.expected_close_on,
		// Present only for a member who may see money. Absent, not null, for everyone else.
		...(canViewValue ? { estimated_value: row.estimated_value } : {}),
		request: row.request_id ? { id: row.request_id, status: row.request_status } : null,
		// A quote whose latest email bounced, was refused, or never left says so. The address is already
		// withheld by the database from a member who may not see this client.
		quote: row.quote_id
			? {
					id: row.quote_id,
					status: row.quote_status as string,
					delivery_failure:
						row.quote_delivery_failure && row.quote_delivery_failed_at
							? {
									reason: row.quote_delivery_failure,
									failed_at: row.quote_delivery_failed_at,
									recipient_email: row.quote_delivery_failed_email
								}
							: null
				}
			: null,
		// A member who may not see this client gets the card without the client's details, exactly as
		// the clients table would have answered.
		client:
			row.client_display_name === null
				? null
				: {
						id: row.client_id,
						display_name: row.client_display_name,
						company_name: row.client_company_name,
						// Where this client came from, or null when nobody recorded it.
						lead_source: row.client_lead_source
					},
		property:
			row.property_id === null || row.property_address_line1 === null
				? null
				: {
						id: row.property_id,
						label: row.property_label,
						address_line1: row.property_address_line1,
						city: row.property_city,
						state_region: row.property_state_region,
						postal_code: row.property_postal_code
					},
		// The name is missing when the owner has left the team; the ownership itself is kept.
		owner: row.owner_user_id
			? {
					id: row.owner_user_id,
					full_name: row.owner_full_name,
					avatar_url: row.owner_avatar_url
				}
			: null,
		// The card's one open Task, in the same priority order the Brief's own list uses. Null when the
		// Opportunity has none open.
		task: row.task_id
			? { id: row.task_id, title: row.task_title as string, due_on: row.task_due_on }
			: null,
		// The booked visit, present only once somebody has scheduled one. The collapsed Assessment column
		// shows three sub-states in one place, and "scheduled" is only a useful thing to read on a card if
		// it also says when — the Request status alone cannot answer that.
		assessment: row.assessment_starts_at
			? { starts_at: row.assessment_starts_at, ends_at: row.assessment_ends_at }
			: null
	};
}
