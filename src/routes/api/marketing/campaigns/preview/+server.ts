import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	marketingPreviewContentSchema,
	type MarketingCampaignContent
} from '$lib/marketing/campaign-content';
import { hydrateRuleLabels } from '$lib/server/marketing/customer-groups';
import { getMarketingBusinessIdentity } from '$lib/server/marketing/business-identity';
import {
	renderCampaignEmail,
	resolveMarketingVariablesPlainText
} from '$lib/server/marketing/render-email';
import { resolveMarketingCtaTarget } from '$lib/server/marketing/call-to-action';
import { createPresignedPreviewImageUrl } from '$lib/server/storage/r2';

// The block editor's live preview: content in, rendered email out. No campaign id -- a draft that has not
// been saved yet still needs to preview. Read-only, so marketing.view is enough, same as the customer-groups
// preview route. Uses a representative sample name and the organization's real business identity, never a
// raw {{token}}, matching the blueprint's "no leaking a placeholder" rule.

// The content may still be half-written (marketingPreviewContentSchema): the Email step previews as you type.
// `mark_blocks` is the editor's own switch (see MarketingRenderContext.markBlocks); the review step and the
// template pop-up leave it off.
const previewSchema = z.object({
	content: marketingPreviewContentSchema,
	mark_blocks: z.boolean().optional()
});

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'marketing.view');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = previewSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;
	// Only an image block's not-yet-uploaded photo ('') differs from saved content; the renderer draws it as a
	// stand-in.
	const content = parsed.data.content as MarketingCampaignContent;
	const catalogItemIds = content.blocks
		.filter((block) => block.type === 'service_summary')
		.flatMap((block) => (block.type === 'service_summary' ? block.catalog_item_ids : []));

	try {
		const [business, labels, cta] = await Promise.all([
			getMarketingBusinessIdentity(organizationId, access.auth.organization.name),
			hydrateRuleLabels(organizationId, catalogItemIds, []),
			resolveMarketingCtaTarget(organizationId, content.cta, event.url.origin)
		]);
		const serviceNames = Object.fromEntries(
			labels.catalog_items.map((item) => [item.id, item.label])
		);
		// The preview renders in a sandboxed iframe that sends no session cookie, so each picture gets a
		// short-lived signed link instead. The member's own client is the permission check: RLS only returns
		// Files this reader may see, and only a scanned, untrashed image is ever signed.
		const imageFileIds = content.blocks.flatMap((block) =>
			block.type === 'image' && block.file_id ? [block.file_id] : []
		);
		const imageUrls: Record<string, string> = {};
		if (imageFileIds.length > 0) {
			const { data: files, error } = await event.locals.supabase
				.from('files')
				.select('id, object_key, mime_type')
				.in('id', imageFileIds)
				.eq('processing_state', 'available')
				.is('trashed_at', null);
			if (error) throw error;
			for (const file of files) {
				if (file.mime_type.startsWith('image/'))
					imageUrls[file.id] = await createPresignedPreviewImageUrl(file.object_key);
			}
		}

		const variables = { customer_first_name: 'Alex', business_name: business.name };
		const rendered = await renderCampaignEmail(content, {
			variables,
			serviceNames,
			imageUrls,
			business,
			unsubscribeUrl: null,
			cta,
			markBlocks: parsed.data.mark_blocks
		});
		// The inbox line above the email in the editor: the sender, and the subject and preview text as a
		// customer would read them (variables filled with the same sample values).
		return json(
			{
				...rendered,
				sender_name: business.name,
				subject: resolveMarketingVariablesPlainText(content.subject, variables),
				preview_text: resolveMarketingVariablesPlainText(content.preview_text ?? '', variables)
			},
			{ headers: NO_STORE_HEADERS }
		);
	} catch (error) {
		console.error('Could not render a marketing campaign preview.', error);
		return databaseError();
	}
};
