import { json } from '@sveltejs/kit';
import { z } from 'zod';
import { supportTopicSchema } from '$lib/server/validation/support.schema';
import type { SupportTopic } from '$lib/support/api';

// Changing a chat's topic (D4a), shared by the member route and the /jafar route. The database functions
// decide who may change it and write the grey "changed the topic" line; this only reads the request.
export async function readTopicChange(
	params: { threadId?: string },
	request: Request
): Promise<{ threadId: string; topic: SupportTopic } | { response: Response }> {
	const threadId = z.string().uuid().safeParse(params.threadId);
	if (!threadId.success)
		return { response: json({ error: 'That conversation could not be found.' }, { status: 404 }) };

	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return { response: json({ error: 'Request body must be valid JSON.' }, { status: 400 }) };
	}
	const parsed = supportTopicSchema.safeParse(body);
	if (!parsed.success)
		return {
			response: json(
				{
					error: 'Choose one of the listed topics.',
					field_errors: { topic: 'Choose one of the listed topics.' }
				},
				{ status: 422 }
			)
		};
	return { threadId: threadId.data, topic: parsed.data.topic };
}
