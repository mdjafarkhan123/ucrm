import { z } from 'zod';
import { isDangerousAttachmentName } from '$lib/communications/attachment-limits';
import {
	SUPPORT_ATTACHMENT_TOTAL_BYTES,
	SUPPORT_MAX_ATTACHMENTS,
	SUPPORT_MAX_LOADED,
	SUPPORT_MESSAGE_MAX_LENGTH,
	SUPPORT_PAGE_SIZE,
	SUPPORT_TOPIC_VALUES
} from '$lib/support/api';

const supportTopicField = z.enum(SUPPORT_TOPIC_VALUES, {
	error: 'Choose one of the listed topics.'
});

// A file's name as its sender gave it. Program files are refused, by the customer inbox's own list.
const supportFileName = z
	.string()
	.trim()
	.min(1, 'Choose a file.')
	.max(255, 'That file name is too long.')
	.refine((name) => !isDangerousAttachmentName(name), {
		message: 'That file type is not allowed.'
	});

const supportMimeType = z.string().trim().min(1).max(127);

// Asking for somewhere to upload one file, before the message that carries it is sent.
export const supportAttachmentPresignSchema = z.object({
	file_name: supportFileName,
	mime_type: supportMimeType,
	size_bytes: z
		.number()
		.int()
		.positive('That file is empty.')
		.max(SUPPORT_ATTACHMENT_TOTAL_BYTES, 'Files must be 20 MB or smaller.')
});

// A file already uploaded. Its size is never taken from the browser: the route measures it in storage.
const supportAttachmentSchema = z.object({
	object_key: z.string().min(1).max(1024),
	file_name: supportFileName,
	mime_type: supportMimeType,
	has_thumbnail: z.boolean().default(false)
});

const supportMessageFields = z.object({
	body: z
		.string()
		.trim()
		.max(
			SUPPORT_MESSAGE_MAX_LENGTH,
			`Keep a message under ${SUPPORT_MESSAGE_MAX_LENGTH} characters.`
		),
	client_message_id: z.string().uuid('Send the message again.'),
	attachments: z
		.array(supportAttachmentSchema)
		.max(SUPPORT_MAX_ATTACHMENTS, `Attach at most ${SUPPORT_MAX_ATTACHMENTS} files to one message.`)
		.default([])
});

// A message is words, files, or both — never neither.
const hasContent = (message: { body: string; attachments: unknown[] }) =>
	message.body.length > 0 || message.attachments.length > 0;
const NEEDS_CONTENT = { path: ['body'], message: 'Write a message or attach a file first.' };

// One message, from either side. The id is chosen by the sender's browser so a retry after a dropped
// connection can never post the same message twice.
export const supportMessageSchema = supportMessageFields.refine(hasContent, NEEDS_CONTENT);

// A member's message in a chat they can see.
export const supportMemberMessageSchema = supportMessageFields
	.extend({ thread_id: z.string().uuid() })
	.refine(hasContent, NEEDS_CONTENT);

// A new chat and its first message (D4a). The topic is optional and starts as Other.
export const supportStartThreadSchema = supportMessageFields
	.extend({ topic: supportTopicField.default('other') })
	.refine(hasContent, NEEDS_CONTENT);

export const supportTopicSchema = z.object({ topic: supportTopicField });

// Uplift starts a chat with one active team member of a business (D5a).
export const supportUpliftStartThreadSchema = supportMessageFields
	.extend({
		organization_id: z.string().uuid('Choose a business.'),
		user_id: z.string().uuid('Choose who to write to.'),
		topic: supportTopicField.default('other')
	})
	.refine(hasContent, NEEDS_CONTENT);

// Uplift marks a chat Solved, or reopens it (D5a).
export const supportStatusSchema = z.object({
	status: z.enum(['open', 'solved'], { error: 'Choose open or solved.' })
});

export const supportThreadQuerySchema = z.object({
	limit: z.coerce.number().int().min(1).max(SUPPORT_MAX_LOADED).default(SUPPORT_PAGE_SIZE)
});

export const supportMemberThreadQuerySchema = supportThreadQuerySchema.extend({
	thread_id: z.string().uuid()
});

// The Support Inbox, optionally narrowed to one topic. Open chats unless asked otherwise.
export const supportInboxQuerySchema = supportThreadQuerySchema.extend({
	topic: supportTopicField.optional(),
	status: z.enum(['open', 'solved', 'all']).default('open')
});

// Adding a teammate to a conversation (D3).
export const supportPersonSchema = z.object({
	user_id: z.string().uuid('Choose a teammate.')
});

export const supportSettingsSchema = z.object({
	responder_name: z
		.string()
		.trim()
		.min(1, 'Add the name clients see on your replies.')
		.max(80, 'Keep the name under 80 characters.'),
	availability_note: z.string().trim().max(160, 'Keep this under 160 characters.')
});

// "Seen up to here": the time of the newest message the reader's screen showed. The database never lets a
// mark move backwards or past the present, so a stale or invented time cannot hide a later message.
const readThroughSchema = z.string().datetime({ offset: true });

export const supportMemberReadSchema = z.object({
	thread_id: z.string().uuid(),
	read_through: readThroughSchema
});

export const supportUpliftReadSchema = z.object({ read_through: readThroughSchema });
