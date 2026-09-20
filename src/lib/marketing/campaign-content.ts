import { z } from 'zod';

// A campaign's email content: subject, preview text, and an ordered list of blocks. Validated here (before
// it reaches the API) and the database only guards that it is a json object -- same split as
// src/lib/forms/types.ts + forms.schema.ts for the request/booking form builder, the closest existing
// precedent for a bounded, ordered content document.
//
// `.strict()` on every object matters: an unknown key is a mistake or an attack, and both should stop here.

export const MARKETING_BLOCK_TYPES = [
	'image',
	'heading',
	'text',
	'button',
	'divider',
	'service_summary'
] as const;
export type MarketingBlockType = (typeof MARKETING_BLOCK_TYPES)[number];

// Caps. Bounded on purpose -- an email stays a fast, predictable render and safe to store. The editor shows
// these as limits; the validator refuses past them.
export const MARKETING_MAX_BLOCKS = 30;
export const MARKETING_SUBJECT_MAX = 150;
export const MARKETING_PREVIEW_TEXT_MAX = 150;
export const MARKETING_HEADING_TEXT_MAX = 160;
export const MARKETING_TEXT_BLOCK_MAX = 4000;
export const MARKETING_BUTTON_LABEL_MAX = 40;
export const MARKETING_IMAGE_ALT_MAX = 200;
export const MARKETING_SERVICE_SUMMARY_TITLE_MAX = 120;
export const MARKETING_SERVICE_SUMMARY_MAX_ITEMS = 6;
export const MARKETING_CAMPAIGN_NAME_MAX = 160;

// Approved merge fields. Never freeform: the editor offers these from a picker, so a saved draft can never
// contain a token this list does not already know how to resolve. Missing-value handling per recipient (a
// customer with no first name on file) is M4's job at launch time -- this only prevents an unknown token
// from ever being saved.
export const MARKETING_VARIABLES = ['customer_first_name', 'business_name'] as const;
export type MarketingVariable = (typeof MARKETING_VARIABLES)[number];

const httpUrl = z
	.string()
	.trim()
	.min(1)
	.refine((value) => value === '#' || /^https?:\/\//i.test(value), {
		message: 'Enter a full web address starting with https://.'
	});

// Finds every {{...}} token in a string and rejects the field if any is outside MARKETING_VARIABLES.
// "#var" names the failing token in the message so the correction is concrete, not a generic rejection.
function rejectUnknownVariables(value: string, ctx: z.RefinementCtx) {
	const tokens = value.match(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g) ?? [];
	for (const token of tokens) {
		const name = token.replace(/[{}\s]/g, '');
		if (!(MARKETING_VARIABLES as readonly string[]).includes(name)) {
			ctx.addIssue({
				code: z.ZodIssueCode.custom,
				message: `"${'{{' + name + '}}'}" is not a variable this app knows. Pick one from the variable list.`
			});
		}
	}
}

const variableText = (max: number) =>
	z.string().trim().min(1).max(max).superRefine(rejectUnknownVariables);

const blockId = z.string().uuid();

export const marketingImageBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('image'),
		url: httpUrl,
		alt: z.string().trim().max(MARKETING_IMAGE_ALT_MAX).default(''),
		link_url: httpUrl.optional()
	})
	.strict();

export const marketingHeadingBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('heading'),
		level: z.enum(['h1', 'h2']),
		text: variableText(MARKETING_HEADING_TEXT_MAX)
	})
	.strict();

export const marketingTextBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('text'),
		text: variableText(MARKETING_TEXT_BLOCK_MAX)
	})
	.strict();

export const marketingButtonBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('button'),
		label: variableText(MARKETING_BUTTON_LABEL_MAX),
		url: httpUrl
	})
	.strict();

export const marketingDividerBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('divider')
	})
	.strict();

export const marketingServiceSummaryBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('service_summary'),
		title: z.string().trim().min(1).max(MARKETING_SERVICE_SUMMARY_TITLE_MAX),
		catalog_item_ids: z.array(z.string().uuid()).max(MARKETING_SERVICE_SUMMARY_MAX_ITEMS)
	})
	.strict();

export const marketingBlockSchema = z.discriminatedUnion('type', [
	marketingImageBlockSchema,
	marketingHeadingBlockSchema,
	marketingTextBlockSchema,
	marketingButtonBlockSchema,
	marketingDividerBlockSchema,
	marketingServiceSummaryBlockSchema
]);

export type MarketingBlock = z.infer<typeof marketingBlockSchema>;

export const marketingCampaignContentSchema = z
	.object({
		version: z.literal('1'),
		// Empty is allowed here: a draft is saveable at any point in the journey, before the Email step (3)
		// has even been built. M4's Send/Schedule action is what will require a non-empty subject.
		subject: z.string().trim().max(MARKETING_SUBJECT_MAX).superRefine(rejectUnknownVariables),
		preview_text: z
			.string()
			.trim()
			.max(MARKETING_PREVIEW_TEXT_MAX)
			.superRefine(rejectUnknownVariables)
			.optional()
			.transform((value) => (value ? value : undefined))
			.optional(),
		blocks: z.array(marketingBlockSchema).max(MARKETING_MAX_BLOCKS)
	})
	.strict();

export type MarketingCampaignContent = z.infer<typeof marketingCampaignContentSchema>;

export const emptyMarketingCampaignContent: MarketingCampaignContent = {
	version: '1',
	subject: '',
	blocks: []
};

export const marketingGoals = ['bring_back', 'promote_service', 'announcement', 'blank'] as const;
export type MarketingGoal = (typeof marketingGoals)[number];

export const marketingGoalLabels: Record<MarketingGoal, string> = {
	bring_back: 'Bring past customers back',
	promote_service: 'Promote a seasonal or additional service',
	announcement: 'Send an announcement',
	blank: 'Start from a blank campaign'
};

// Step 1's card copy (blueprint §8 step 1): who this goal is meant to reach.
export const marketingGoalDescriptions: Record<MarketingGoal, string> = {
	bring_back: 'Reach customers who have not booked in a while and invite them back.',
	promote_service: 'Tell existing customers about a seasonal or additional service.',
	announcement: 'Share news — a price change, new hours, or something new you offer.',
	blank: 'Build the email yourself with no starting content.'
};

export const marketingCampaignStatuses = [
	'draft',
	'scheduled',
	'sending',
	'completed',
	'cancelled',
	'needs_attention'
] as const;
export type MarketingCampaignStatus = (typeof marketingCampaignStatuses)[number];

export const marketingCampaignStatusLabels: Record<MarketingCampaignStatus, string> = {
	draft: 'Draft',
	scheduled: 'Scheduled',
	sending: 'Sending',
	completed: 'Completed',
	cancelled: 'Cancelled',
	needs_attention: 'Needs attention'
};

// Same five-tone system as Quotes' STORED_QUOTE_STATUSES (src/lib/quotes/statuses.ts).
export const marketingCampaignStatusTones: Record<
	MarketingCampaignStatus,
	'success' | 'critical' | 'warning' | 'informative' | 'inactive'
> = {
	draft: 'inactive',
	scheduled: 'informative',
	sending: 'warning',
	completed: 'success',
	cancelled: 'inactive',
	needs_attention: 'critical'
};

export type MarketingCampaignListItem = {
	id: string;
	name: string;
	goal: MarketingGoal;
	status: MarketingCampaignStatus;
	customer_group_id: string | null;
	updated_at: string;
};

export type MarketingCampaign = MarketingCampaignListItem & {
	template_id: string | null;
	content: MarketingCampaignContent;
	revision: number;
};

export const marketingCampaignsKey = ['marketing', 'campaigns'] as const;
export const marketingCampaignKey = (id: string) => ['marketing', 'campaigns', id] as const;
export const marketingCampaignPreviewKey = (content: MarketingCampaignContent) =>
	['marketing', 'campaigns', 'preview', content] as const;
export const marketingTemplatesKey = ['marketing', 'templates'] as const;
