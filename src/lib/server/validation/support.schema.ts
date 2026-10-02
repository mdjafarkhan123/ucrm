import { z } from 'zod';
import {
	SUPPORT_MAX_LOADED,
	SUPPORT_MESSAGE_MAX_LENGTH,
	SUPPORT_PAGE_SIZE,
	SUPPORT_TOPIC_VALUES
} from '$lib/support/api';

const supportTopicField = z.enum(SUPPORT_TOPIC_VALUES, {
	error: 'Choose one of the listed topics.'
});

// One message, from either side. The id is chosen by the sender's browser so a retry after a dropped
// connection can never post the same message twice.
export const supportMessageSchema = z.object({
	body: z
		.string()
		.trim()
		.min(1, 'Write a message first.')
		.max(
			SUPPORT_MESSAGE_MAX_LENGTH,
			`Keep a message under ${SUPPORT_MESSAGE_MAX_LENGTH} characters.`
		),
	client_message_id: z.string().uuid('Send the message again.')
});

// A member's message in a chat they can see.
export const supportMemberMessageSchema = supportMessageSchema.extend({
	thread_id: z.string().uuid()
});

// A new chat and its first message (D4a). The topic is optional and starts as Other.
export const supportStartThreadSchema = supportMessageSchema.extend({
	topic: supportTopicField.default('other')
});

export const supportTopicSchema = z.object({ topic: supportTopicField });

export const supportThreadQuerySchema = z.object({
	limit: z.coerce.number().int().min(1).max(SUPPORT_MAX_LOADED).default(SUPPORT_PAGE_SIZE)
});

export const supportMemberThreadQuerySchema = supportThreadQuerySchema.extend({
	thread_id: z.string().uuid()
});

// The Support Inbox, optionally narrowed to one topic.
export const supportInboxQuerySchema = supportThreadQuerySchema.extend({
	topic: supportTopicField.optional()
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
