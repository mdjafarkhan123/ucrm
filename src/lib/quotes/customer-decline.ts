// Why a customer said no, in their own words (Pipeline B8). Offered on the quote link's Decline step and
// shown back to staff in Sales Outcomes. These are the customer's picks, worded the way a homeowner would
// say them, and are never the same list as the team's own Lost reasons.
export const CUSTOMER_DECLINE_REASONS = [
	'too_expensive',
	'went_with_someone_else',
	'no_longer_needed',
	'other'
] as const;

export type CustomerDeclineReason = (typeof CUSTOMER_DECLINE_REASONS)[number];

export const CUSTOMER_DECLINE_REASON_LABELS: Record<CustomerDeclineReason, string> = {
	too_expensive: 'Too expensive',
	went_with_someone_else: 'Went with someone else',
	no_longer_needed: 'No longer doing the work',
	other: 'Other'
};
