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

export const MARKETING_BLOCK_TYPE_LABELS: Record<MarketingBlockType, string> = {
	image: 'Image',
	heading: 'Heading',
	text: 'Text',
	button: 'Button',
	divider: 'Divider',
	service_summary: 'Service summary'
};

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

export const MARKETING_VARIABLE_LABELS: Record<MarketingVariable, string> = {
	customer_first_name: "Customer's first name",
	business_name: 'Your business name'
};

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

// Part 6F: the image comes from the File Manager, not a pasted address. file_id names an uploaded File this
// organization owns; render-email.ts resolves it to an actual URL at render/send time (never stored here --
// the same split serviceNames already uses for service_summary's catalog item ids).
export const marketingImageBlockSchema = z
	.object({
		id: blockId,
		type: z.literal('image'),
		file_id: z.string().uuid(),
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

// The primary campaign action (blueprint §8 step 4): an existing UCRM Request/Booking form, the business's
// own website, or a phone-call button. Only the chosen form's id is stored -- website and phone read the
// live Business Profile fields at display and send time, the same "still exists" check the form option
// needs, so there is nothing else to freeze into a draft.
export const MARKETING_CTA_TYPES = ['internal_form', 'website', 'phone'] as const;
export type MarketingCtaType = (typeof MARKETING_CTA_TYPES)[number];

export const marketingCtaSchema = z.discriminatedUnion('type', [
	z.object({ type: z.literal('internal_form'), form_id: z.string().uuid() }).strict(),
	z.object({ type: z.literal('website') }).strict(),
	z.object({ type: z.literal('phone') }).strict()
]);
export type MarketingCta = z.infer<typeof marketingCtaSchema>;

export const MARKETING_CTA_TYPE_LABELS: Record<MarketingCtaType, string> = {
	internal_form: 'An existing form',
	website: 'Your website',
	phone: 'A phone call'
};

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
		blocks: z.array(marketingBlockSchema).max(MARKETING_MAX_BLOCKS),
		cta: marketingCtaSchema
			.nullable()
			.optional()
			.transform((value) => value ?? null)
	})
	.strict();

export type MarketingCampaignContent = z.infer<typeof marketingCampaignContentSchema>;

export const emptyMarketingCampaignContent: MarketingCampaignContent = {
	version: '1',
	subject: '',
	blocks: [],
	cta: null
};

// The editor deep-clones a loaded draft before touching it (never mutate a TanStack Query cache entry in
// place -- same reason the request-form builder's `cloneContent` exists) and normalizes `preview_text` to an
// always-defined string, since the editor's Input needs a stable string to bind, not `string | undefined`.
export function cloneMarketingCampaignContent(
	content: MarketingCampaignContent
): MarketingCampaignContent {
	const clone = structuredClone(content);
	clone.preview_text ??= '';
	clone.cta ??= null;
	return clone;
}

// A friendly, client-side mirror of the block-level Zod requirements above -- the server stays the source of
// truth (CLAUDE.md rule 12); this only spares a round trip and names the exact block, the same split the
// request-form builder's own `validate()` uses.
export function describeMarketingContentProblem(content: MarketingCampaignContent): string | null {
	for (let i = 0; i < content.blocks.length; i++) {
		const block = content.blocks[i];
		const position = `Block ${i + 1} (${MARKETING_BLOCK_TYPE_LABELS[block.type]})`;
		switch (block.type) {
			case 'heading':
			case 'text':
				if (!block.text.trim()) return `${position} needs its text.`;
				break;
			case 'button':
				if (!block.label.trim()) return `${position} needs its button label.`;
				if (!block.url.trim()) return `${position} needs a link.`;
				break;
			case 'image':
				if (!block.file_id) return `${position} needs a photo.`;
				break;
			case 'service_summary':
				if (!block.title.trim()) return `${position} needs a title.`;
				break;
			case 'divider':
				break;
		}
	}
	return null;
}

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

// --- M5c: campaign detail tabs (blueprint §12-13) ---------------------------------------------------------

// The recipient status check constraint's exact values (marketing_campaign_recipients_status_check).
export const marketingRecipientStatuses = [
	'waiting',
	'checking',
	'submitted',
	'delivered',
	'bounced',
	'complained',
	'unsubscribed',
	'cancelled',
	'failed',
	'excluded'
] as const;
export type MarketingRecipientStatus = (typeof marketingRecipientStatuses)[number];

export const marketingRecipientStatusLabels: Record<MarketingRecipientStatus, string> = {
	waiting: 'Waiting',
	checking: 'Checking',
	submitted: 'Submitted',
	delivered: 'Delivered',
	bounced: 'Bounced',
	complained: 'Complained',
	unsubscribed: 'Unsubscribed',
	cancelled: 'Cancelled',
	failed: 'Failed',
	excluded: 'Excluded'
};

export const marketingRecipientStatusTones: Record<
	MarketingRecipientStatus,
	'success' | 'critical' | 'warning' | 'informative' | 'inactive'
> = {
	waiting: 'informative',
	checking: 'informative',
	submitted: 'warning',
	delivered: 'success',
	bounced: 'critical',
	complained: 'critical',
	unsubscribed: 'warning',
	cancelled: 'inactive',
	failed: 'critical',
	excluded: 'inactive'
};

export const marketingExcludedReasonLabels: Record<string, string> = {
	inactive_customer: 'Inactive customer',
	missing_email: 'No email on file',
	complaint: 'Marked a past email as spam',
	unsubscribed: 'Unsubscribed from marketing',
	hard_bounce: 'A past email bounced',
	do_not_disturb: 'Do not disturb',
	no_marketing: 'Marketing not allowed for this customer',
	no_consent: 'No marketing consent on file',
	duplicate_destination: 'Duplicate email address'
};

export type MarketingCampaignRecipientBucketCounts = {
	waiting: number;
	submitted: number;
	delivered: number;
	failed_excluded: number;
	cancelled: number;
};

export type MarketingCampaignOverview = MarketingCampaign & {
	created_at: string;
	scheduled_for: string | null;
	launched_at: string | null;
	launched_by: string | null;
	recipient_total_count: number | null;
	recipient_eligible_count: number | null;
	recipient_excluded_count: number | null;
	customer_group_name: string | null;
	counts: MarketingCampaignRecipientBucketCounts;
};

// A recipient's attribution, when this campaign has one: `source` names whether the customer used the
// campaign's own call-to-action link (tracked) or staff connected the work after review (declared) --
// blueprint §13's "the UI names which method was used."
export type MarketingCampaignRecipientCredit = {
	source: 'tracked' | 'declared';
	request_id: string | null;
	job_id: string | null;
};

export type MarketingCampaignRecipient = {
	id: string;
	client_id: string;
	display_name: string;
	recipient_email: string | null;
	status: string;
	excluded_reason: string | null;
	delivered_at: string | null;
	first_opened_at: string | null;
	first_clicked_at: string | null;
	unsubscribed_at: string | null;
	credit: MarketingCampaignRecipientCredit | null;
};

export type MarketingCampaignRecipientsPage = {
	recipients: MarketingCampaignRecipient[];
	next_cursor: string | null;
};

export type MarketingCampaignRecipientFilter =
	'waiting' | 'delivered' | 'failed' | 'excluded' | 'unsubscribed' | 'engaged';

export type MarketingCampaignCreditedWork = {
	credit_id: string;
	source: 'tracked' | 'declared';
	request_id: string | null;
	job_id: string | null;
	client_id: string;
	client_name: string;
	credited_at: string;
	work_title: string | null;
	work_created_at: string | null;
	revenue_minor: number;
};

export type MarketingCampaignResults = {
	matched_count: number;
	eligible_count: number;
	excluded_count: number;
	submitted_count: number;
	delivered_count: number;
	bounced_count: number;
	complained_count: number;
	unsubscribed_count: number;
	opened_count: number;
	clicked_count: number;
	credited_work: MarketingCampaignCreditedWork[];
	revenue_minor: number;
	currency_code: string;
};

export type MarketingWindowAttributionCandidate = {
	work_kind: 'request' | 'job';
	request_id: string | null;
	job_id: string | null;
	client_id: string;
	client_name: string;
	work_title: string | null;
	work_created_at: string;
	delivered_at: string;
};

export const marketingCampaignOverviewKey = (id: string) =>
	['marketing', 'campaigns', id, 'overview'] as const;
export const marketingCampaignRecipientsKey = (
	id: string,
	filters: { statusFilter?: MarketingCampaignRecipientFilter | ''; search?: string }
) => ['marketing', 'campaigns', id, 'recipients', filters] as const;
export const marketingCampaignResultsKey = (id: string) =>
	['marketing', 'campaigns', id, 'results'] as const;
export const marketingCampaignAttributionCandidatesKey = (id: string) =>
	['marketing', 'campaigns', id, 'attribution-candidates'] as const;
