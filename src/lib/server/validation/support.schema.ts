import { z } from 'zod';
import {
	SUPPORT_MAX_LOADED,
	SUPPORT_MESSAGE_MAX_LENGTH,
	SUPPORT_PAGE_SIZE
} from '$lib/support/api';

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

export const supportThreadQuerySchema = z.object({
	limit: z.coerce.number().int().min(1).max(SUPPORT_MAX_LOADED).default(SUPPORT_PAGE_SIZE)
});

export const supportSettingsSchema = z.object({
	responder_name: z
		.string()
		.trim()
		.min(1, 'Add the name clients see on your replies.')
		.max(80, 'Keep the name under 80 characters.'),
	availability_note: z.string().trim().max(160, 'Keep this under 160 characters.')
});
