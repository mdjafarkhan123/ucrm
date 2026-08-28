import { z } from 'zod';
import {
	attachmentExtension,
	DANGEROUS_ATTACHMENT_EXTENSIONS,
	INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES
} from '$lib/server/communications/inbound-email';

// A file we would refuse to receive is one we refuse to send -- both directions share the same 20 MB
// total and dangerous-extension block list (docs/contractor-email-contract.md § Attachments).
const MAX_OUTBOUND_ATTACHMENTS_PER_MESSAGE = 10;

export const outboundAttachmentPresignSchema = z.object({
	file_name: z
		.string()
		.trim()
		.min(1, 'Choose a file.')
		.max(255)
		.refine((name) => !DANGEROUS_ATTACHMENT_EXTENSIONS.has(attachmentExtension(name)), {
			message: 'That file type is not allowed.'
		}),
	mime_type: z.string().trim().min(1).max(127),
	size_bytes: z
		.number()
		.int()
		.positive()
		.max(INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES, 'Files must be 20 MB or smaller.')
});

// What the send routes accept once a file has already been uploaded: only enough to look it back up and
// re-measure it (headObject), never a browser-claimed size. The private attach command re-enforces the
// per-org key prefix, the 20 MB total, and the 10-file cap; this cap just fails fast client-side.
const outboundAttachmentSchema = z.object({
	object_key: z.string().trim().min(1),
	file_name: z.string().trim().min(1).max(255),
	mime_type: z.string().trim().min(1).max(127)
});

const outboundAttachmentsField = z
	.array(outboundAttachmentSchema)
	.max(MAX_OUTBOUND_ATTACHMENTS_PER_MESSAGE, 'Attach at most 10 files to one email.')
	.default([]);

const senderConfiguration = {
	display_name: z.string().trim().min(1, 'Enter a sender name.').max(160),
	assigned_user_id: z.string().uuid('Choose an active team member.').nullable(),
	is_organization_default: z.boolean(),
	allows_manual: z.boolean(),
	allows_automated: z.boolean()
};

export const communicationSenderCreateSchema = z
	.object({
		domain_id: z.string().uuid('Choose a verified sending domain.'),
		email_address: z.string().trim().toLowerCase().email('Enter a valid email address.').max(320),
		...senderConfiguration,
		idempotency_key: z.string().uuid('Start a new sender attempt and try again.')
	})
	.refine((value) => value.allows_manual || value.allows_automated, {
		message: 'Allow manual or automated email.',
		path: ['allows_manual']
	});

export const communicationSenderUpdateSchema = z
	.object({
		...senderConfiguration,
		enabled: z.boolean(),
		idempotency_key: z.string().uuid('Start a new sender change and try again.')
	})
	.refine((value) => !value.enabled || value.allows_manual || value.allows_automated, {
		message: 'An enabled sender must allow manual or automated email.',
		path: ['allows_manual']
	});

const websiteChatChannelOption = z.object({
	type: z.enum(['whatsapp', 'messenger']),
	destination: z.string().trim().min(1, 'Enter a destination.').max(300)
});

const websiteChatWidgetConfiguration = {
	name: z.string().trim().min(1, 'Give this widget a name.').max(120),
	launcher_position: z.enum(['bottom_left', 'bottom_right']),
	teaser_text: z.string().trim().max(300).nullable(),
	greeting_text: z.string().trim().max(300).nullable(),
	contact_requirement: z.enum(['phone', 'email', 'either']),
	availability_visibility_mode: z.enum(['hidden', 'show_when_available', 'always']),
	source_label: z.string().trim().max(120).nullable(),
	// The identity form links to the contractor's own policy, never the platform's. https only: the
	// widget renders this straight into an anchor on someone else's website, so a `javascript:` or
	// `data:` value must never survive validation.
	privacy_policy_url: z
		.string()
		.trim()
		.max(500, 'Use a privacy policy link up to 500 characters.')
		.refine(
			(value) => value === '' || /^https:\/\/\S+$/.test(value),
			'Enter a privacy policy link starting with https://.'
		)
		.nullable()
		.transform((value) => (value ? value : null)),
	channel_options: z.array(websiteChatChannelOption).max(5).default([])
};

export const websiteChatWidgetCreateSchema = z.object(websiteChatWidgetConfiguration);

export const websiteChatWidgetUpdateSchema = z.object({
	...websiteChatWidgetConfiguration,
	expected_revision: z.number().int().nonnegative(),
	published: z.boolean(),
	disabled: z.boolean()
});

const originPattern =
	/^https?:\/\/[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+(:[0-9]{1,5})?$/;

export const websiteChatWidgetOriginCreateSchema = z.object({
	origin: z
		.string()
		.trim()
		.toLowerCase()
		.max(2048)
		.refine((value) => originPattern.test(value), {
			message: 'Enter a valid origin like https://example.com.'
		})
});

export const websiteChatWidgetInstallTestSchema = z.object({
	url: z.string().trim().max(2048).url('Enter a valid page URL.')
});

// --- Public Website Chat widget payloads (WC4.2) ----------------------------------------------------
//
// These are the only Communications bodies that arrive from an anonymous visitor on a stranger's
// website, so they are validated for shape and size before a single database round trip is spent. A
// body that fails here is answered with the same silent refusal as a bad token: the widget never gets a
// field-level error map back, because a public endpoint that explains itself is an enumeration tool.

// E.164 shape only. Authoritative parsing and normalization with `libphonenumber-js` arrives with the
// identity form in WC4.3; this is the cheap gate that keeps junk out of the command.
const e164Pattern = /^\+[1-9]\d{6,14}$/;

const optionalContactValue = z
	.string()
	.trim()
	.max(320)
	.optional()
	.transform((value) => (value ? value : undefined));

// Landing page, referrer and UTM values, captured by the widget. Bounded in both key count and value
// size so a public caller cannot push an unbounded jsonb document into every session row.
const websiteChatAttribution = z
	.record(z.string().max(64), z.union([z.string().max(512), z.number(), z.boolean(), z.null()]))
	.refine((value) => Object.keys(value).length <= 20)
	.default({});

export const websiteChatFirstMessageSchema = z
	.object({
		idempotency_key: z.string().trim().min(8).max(200),
		// One field, as HighLevel's widget has it; the command splits it at the first space into the
		// Client's first and last name. The minimum is 2, not 1, because `clients.display_name`
		// refuses a single character -- a one-letter name would pass here and fail on the insert.
		name: z.string().trim().min(2).max(120),
		phone: optionalContactValue.refine((value) => !value || e164Pattern.test(value)),
		email: optionalContactValue.refine(
			(value) => !value || z.email().max(320).safeParse(value).success
		),
		message: z.string().trim().min(1).max(5000),
		consent_transactional_sms: z.boolean().default(false),
		attribution: websiteChatAttribution,
		// Honeypot (WC0.3): invisible to a real visitor, so any value at all means a bot.
		company_website: z.string().max(0).optional()
	})
	// The command refuses a session with neither identifier anyway; rejecting it here saves the trip.
	.refine((value) => !!value.phone || !!value.email);

export const websiteChatLaterMessageSchema = z.object({
	message: z.string().trim().min(1).max(5000),
	idempotency_key: z.string().trim().min(8).max(200).optional()
});

// The visitor reading their own conversation back. The cursor is the row value of the oldest message
// the caller already holds; both halves travel together or neither does, because half a cursor silently
// returns the wrong page. Page size is clamped here and again inside the command.
export const websiteChatSessionMessagesQuerySchema = z
	.object({
		before_created_at: z.iso.datetime({ offset: true }).optional(),
		before_id: z.uuid().optional(),
		page_size: z.coerce.number().int().min(1).max(50).optional()
	})
	.refine((value) => Boolean(value.before_created_at) === Boolean(value.before_id));

// --- Suppression removal (Communications Part 7.2) --------------------------------------------------
//
// An organization administrator asking for a blocked address to be unblocked. A hard bounce clears
// straight away; a spam complaint becomes a request Jafar decides. Either way the reason, the evidence
// of verification, and a renewed-consent attestation are all required
// (docs/contractor-email-contract.md § Preferences, consent, and suppressions).
export const communicationSuppressionRemovalRequestSchema = z.object({
	reason: z
		.string()
		.trim()
		.min(3, 'Give a reason of at least 3 characters.')
		.max(1000, 'Keep the reason under 1,000 characters.'),
	evidence: z
		.string()
		.trim()
		.min(1, 'Describe how you confirmed the address is safe to email again.')
		.max(2000, 'Keep the evidence under 2,000 characters.'),
	consent_confirmed: z
		.boolean()
		.refine((value) => value === true, 'Confirm the customer still wants to receive this email.')
});

export function communicationFieldErrors(error: z.ZodError) {
	return Object.fromEntries(
		error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message] as const)
	);
}

export const manualCommunicationEmailSchema = z.object({
	contact_method_id: z.string().uuid('Choose an email address for this customer.'),
	subject: z.string().trim().min(1, 'Enter a subject.').max(998),
	body: z.string().trim().min(1, 'Enter a message.').max(20_000),
	idempotency_key: z.string().uuid('Start a new email attempt and try again.'),
	attachments: outboundAttachmentsField
});

export const conversationReplyEmailSchema = z.object({
	subject: z.string().trim().min(1, 'Enter a subject.').max(998),
	body: z.string().trim().min(1, 'Enter a message.').max(20_000),
	idempotency_key: z.string().uuid('Start a new reply attempt and try again.'),
	attachments: outboundAttachmentsField
});

export const forwardInboundMessageSchema = z.object({
	recipients: z
		.array(z.string().trim().toLowerCase().email('Enter a valid email address.').max(320))
		.min(1, 'Choose at least one recipient.')
		.max(10, 'Choose at most 10 recipients.'),
	subject: z.string().trim().min(1, 'Enter a subject.').max(998),
	body: z.string().trim().min(1, 'Enter a message.').max(20_000),
	attachment_ids: z
		.array(z.string().uuid())
		.max(MAX_OUTBOUND_ATTACHMENTS_PER_MESSAGE, 'Attach at most 10 files to one forward.')
		.default([]),
	idempotency_key: z.string().uuid('Start a new forward attempt and try again.')
});

export const resendCommunicationEmailSchema = z.strictObject({
	idempotency_key: z.string().uuid('Start a new resend attempt and try again.')
});

export const markConversationReadSchema = z.strictObject({
	client_id: z.string().uuid('Choose a valid conversation.')
});

export const assignConversationSchema = z.strictObject({
	assigned_to: z.string().uuid('Choose a valid team member.').nullable()
});

// A guarded conversation is addressed by the sender's email, not a client_id -- it has none yet. Linking
// needs the client to attach it to; dismissing takes no client at all.
export const resolveInboundReviewSchema = z.strictObject({
	sender_email: z
		.string()
		.trim()
		.min(3, 'Choose a valid conversation.')
		.max(320, 'Choose a valid conversation.'),
	resolution: z.enum(['link', 'dismiss']),
	client_id: z.string().uuid('Choose a client to link this conversation to.').nullable()
});

// --- Website Chat, staff side (WC4.5) -----------------------------------------------------------

// A staff reply into a live session. No subject and no attachments: a chat message is a body, the same
// shape the visitor's own send already has. The 5000 cap is the column's own check constraint, so a
// too-long message is refused here rather than by the database.
export const websiteChatStaffMessageSchema = z.strictObject({
	body: z
		.string()
		.trim()
		.min(1, 'Write a message first.')
		.max(5000, 'Keep a reply under 5,000 characters.'),
	// Retrying a send must replay the original message, never write a second bubble. The command's
	// idempotency column accepts 8-200 characters; a uuid sits inside that and matches every other
	// send in the app.
	idempotency_key: z.string().uuid('Start a new reply attempt and try again.')
});

// A conflicting-identity session is assigned to the Client a person chose. There is deliberately no
// dismiss path: the session already holds real messages and has already claimed an allowance unit, so
// it always belongs to somebody.
export const websiteChatResolveIdentitySchema = z.strictObject({
	client_id: z.string().uuid('Choose a client for this conversation.')
});

// --- Snippets (Communications Part 6, first slice) ----------------------------------------------------

export const SNIPPET_PAGE_SIZE_DEFAULT = 50;
export const SNIPPET_PAGE_SIZE_MAX = 100;

// An empty folder always means "no folder" on create -- there is no "leave untouched" state yet to protect.
const optionalSnippetText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullish()
		.transform((value) => value || null);

export const communicationSnippetCreateSchema = z.object({
	folder: optionalSnippetText(60, 'Keep a folder name under 60 characters.'),
	title: z.string().trim().min(1, 'Give this snippet a title.').max(120),
	body: z.string().trim().min(1, 'Enter the snippet text.').max(4000)
});

// Leaving a field out means "do not touch it"; sending an explicit null clears the folder. Matches
// `patchableText` in quotes.schema.ts -- same PATCH semantics, kept local since nothing else shares it yet.
const patchableSnippetText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullable()
		.optional()
		.transform((value) => (value === undefined ? undefined : value || null));

export const communicationSnippetUpdateSchema = z
	.object({
		folder: patchableSnippetText(60, 'Keep a folder name under 60 characters.'),
		title: z.string().trim().min(1, 'Give this snippet a title.').max(120).optional(),
		body: z.string().trim().min(1, 'Enter the snippet text.').max(4000).optional()
	})
	.refine(
		(value) => value.folder !== undefined || value.title !== undefined || value.body !== undefined,
		{ message: 'Nothing to change.', path: ['title'] }
	);

export const communicationSnippetListQuerySchema = z.object({
	folder: z.string().trim().max(60).optional(),
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	cursor: z.string().min(3).max(400).optional(),
	limit: z.coerce
		.number()
		.int()
		.min(1)
		.max(SNIPPET_PAGE_SIZE_MAX)
		.default(SNIPPET_PAGE_SIZE_DEFAULT)
});

// --- Email templates, organization side (Communications Part 6c) --------------------------------------
//
// Copying never accepts client-supplied subject/body: the server reads them off the platform template
// (docs/contractor-email-contract.md § Templates, snippets, and branding) so a copy can never diverge from
// what was actually in the library at copy time. Customization happens afterward through the update schema.

export const EMAIL_TEMPLATE_PAGE_SIZE_DEFAULT = 50;
export const EMAIL_TEMPLATE_PAGE_SIZE_MAX = 100;

const optionalTemplateText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullish()
		.transform((value) => value || null);

export const emailTemplateListQuerySchema = z.object({
	folder: z.string().trim().max(60).optional(),
	search: z
		.string()
		.trim()
		.max(160)
		.optional()
		.transform((value) => value || ''),
	cursor: z.string().min(3).max(400).optional(),
	limit: z.coerce
		.number()
		.int()
		.min(1)
		.max(EMAIL_TEMPLATE_PAGE_SIZE_MAX)
		.default(EMAIL_TEMPLATE_PAGE_SIZE_DEFAULT)
});

// An organization template written from scratch, not copied from the library.
export const emailTemplateCreateSchema = z.object({
	folder: optionalTemplateText(60, 'Keep a folder name under 60 characters.'),
	name: z.string().trim().min(1, 'Give this template a name.').max(120),
	subject: z.string().trim().min(1, 'Enter a subject line.').max(300),
	body: z.string().trim().min(1, 'Enter the template body.').max(50_000)
});

export const emailTemplateCopySchema = z.object({
	source_template_id: z.uuid('Choose a template to copy.'),
	folder: optionalTemplateText(60, 'Keep a folder name under 60 characters.')
});

const patchableTemplateText = (max: number, message: string) =>
	z
		.string()
		.trim()
		.max(max, message)
		.nullable()
		.optional()
		.transform((value) => (value === undefined ? undefined : value || null));

export const emailTemplateUpdateSchema = z
	.object({
		folder: patchableTemplateText(60, 'Keep a folder name under 60 characters.'),
		name: z.string().trim().min(1, 'Give this template a name.').max(120).optional(),
		subject: z.string().trim().min(1, 'Enter a subject line.').max(300).optional(),
		body: z.string().trim().min(1, 'Enter the template body.').max(50_000).optional()
	})
	.refine(
		(value) =>
			value.folder !== undefined ||
			value.name !== undefined ||
			value.subject !== undefined ||
			value.body !== undefined,
		{ message: 'Nothing to change.', path: ['name'] }
	);
