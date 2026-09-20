import { z } from 'zod';

// A customer group is a saved set of rules, never a saved list of people, so its count always follows the
// CRM. The same rule object is validated here (before it reaches the API) and again by
// private.marketing_compile_group_rules in the database, which refuses anything outside this shape.
//
// `.strict()` matters: an unknown key is a mistake or an attack, and both should stop here rather than be
// quietly ignored.

const uuidList = (label: string, max: number) =>
	z
		.array(z.string().uuid(`Choose a valid ${label}.`))
		.min(1)
		.max(max);

export const marketingGroupRulesSchema = z
	.object({
		version: z.literal('1'),
		// Lead or customer state.
		lifecycle: z
			.array(z.enum(['lead', 'customer']))
			.min(1)
			.max(2)
			.optional(),
		tags: uuidList('tag', 50).optional(),
		cities: z.array(z.string().trim().min(1).max(120)).min(1).max(50).optional(),
		lead_sources: z.array(z.string().trim().min(1).max(120)).min(1).max(50).optional(),
		// Catalog items used on a line of one of the customer's jobs.
		services: uuidList('service', 50).optional(),
		work_type: z.enum(['one_off', 'recurring']).optional(),
		last_completed_job: z
			.discriminatedUnion('mode', [
				z.object({ mode: z.literal('never') }).strict(),
				z
					.object({
						mode: z.enum(['within_days', 'before_days']),
						days: z.number().int().min(1).max(3650)
					})
					.strict()
			])
			.optional(),
		upcoming_work: z.boolean().optional(),
		include_client_ids: uuidList('customer', 500).optional(),
		exclude_client_ids: uuidList('customer', 500).optional()
	})
	.strict();

export type MarketingGroupRules = z.infer<typeof marketingGroupRulesSchema>;

export const emptyMarketingGroupRules: MarketingGroupRules = { version: '1' };

// One shared list of condition keys and their plain-English labels -- CustomerGroupRuleBuilder (the editor)
// and CampaignReviewStep (the read-only summary before send) both walk it, so a condition never has two
// different names in the two places a contractor sees it.
export type MarketingGroupRuleConditionKey = Exclude<keyof MarketingGroupRules, 'version'>;

export const MARKETING_GROUP_RULE_CONDITIONS: {
	key: MarketingGroupRuleConditionKey;
	label: string;
}[] = [
	{ key: 'lifecycle', label: 'Lead or customer status' },
	{ key: 'tags', label: 'Has any of these tags' },
	{ key: 'cities', label: 'City or service area' },
	{ key: 'lead_sources', label: 'Original lead source' },
	{ key: 'services', label: 'Used one of these services' },
	{ key: 'work_type', label: 'One-off or recurring work' },
	{ key: 'last_completed_job', label: 'Last completed Job' },
	{ key: 'upcoming_work', label: 'Upcoming work' },
	{ key: 'include_client_ids', label: 'Always include these customers' },
	{ key: 'exclude_client_ids', label: 'Always exclude these customers' }
];

// Every reason a matched customer would not receive the campaign. `recent_marketing` is always 0 until
// launched campaigns exist (M4) and give "already emailed in the last 7 days" a source of truth.
export const marketingExclusionReasons = [
	'inactive_customer',
	'missing_email',
	'unsubscribed',
	'complaint',
	'hard_bounce',
	'do_not_disturb',
	'no_marketing',
	'no_consent',
	'recent_marketing',
	'duplicate_destination'
] as const;

export type MarketingExclusionReason = (typeof marketingExclusionReasons)[number];

// What the contractor reads next to each number. Plain English, no jargon, no blame.
export const marketingExclusionReasonLabels: Record<MarketingExclusionReason, string> = {
	inactive_customer: 'Archived customer',
	missing_email: 'No email address',
	unsubscribed: 'Unsubscribed from your marketing',
	complaint: 'Reported marketing as spam',
	hard_bounce: 'Email address bounced',
	do_not_disturb: 'Do not disturb',
	no_marketing: 'No marketing',
	no_consent: 'No recorded permission',
	recent_marketing: 'Emailed in the last 7 days',
	duplicate_destination: 'Shares an email with another customer'
};

export type MarketingRecipientPreviewCounts = {
	matches: number;
	eligible: number;
	excluded: number;
	excluded_by_reason: Record<MarketingExclusionReason, number>;
};

export type MarketingPreviewRecipient = {
	client_id: string;
	display_name: string;
	email: string | null;
	excluded_reason: MarketingExclusionReason | null;
};

export type MarketingCustomerGroup = {
	id: string;
	name: string;
	description: string | null;
	rules: MarketingGroupRules;
	revision: number;
	updated_at: string;
};

export const marketingCustomerGroupsKey = ['marketing', 'customer-groups'] as const;

export const marketingGroupPreviewKey = (rules: MarketingGroupRules) =>
	['marketing', 'customer-groups', 'preview', rules] as const;
