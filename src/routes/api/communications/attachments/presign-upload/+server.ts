import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	buildOutboundEmailAttachmentObjectKey,
	createPresignedUploadUrl
} from '$lib/server/storage/r2';
import { outboundAttachmentPresignSchema } from '$lib/server/validation/communications.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

const PRESIGN_LIMIT = { windowSeconds: 300, maxAttempts: 40 };

// One presign route serves every composer (reply and New conversation): both send through the same
// paperclip, so both upload into the same <org>/outbound-email-attachments/ prefix before either send
// route ever sees the file. Same gate as sending itself -- attaching a file is part of composing the
// send, not a separate capability.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.send');
	if ('response' in check) return check.response;
	if (!hasPermission(check.access, 'customers.view')) {
		return json(
			{ error: 'You do not have access to this customer.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = outboundAttachmentPresignSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	const limit = await checkRateLimit(ownerClient, {
		bucketKey: `communication_outbound_attachment_presign:${organizationId}:${check.auth.user.id}`,
		...PRESIGN_LIMIT
	});
	if (!limit.allowed) {
		const response = rateLimitedResponse(limit.retryAfterSeconds);
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const objectKey = buildOutboundEmailAttachmentObjectKey(organizationId, parsed.data.file_name);

	let uploadUrl: string;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, parsed.data.mime_type);
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}

	return json({ upload_url: uploadUrl, object_key: objectKey }, { headers: NO_STORE_HEADERS });
};
