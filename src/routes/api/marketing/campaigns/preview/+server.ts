import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { marketingCampaignContentSchema } from '$lib/marketing/campaign-content';
import { hydrateRuleLabels } from '$lib/server/marketing/customer-groups';
import { getMarketingBusinessIdentity } from '$lib/server/marketing/business-identity';
import { renderCampaignEmail } from '$lib/server/marketing/render-email';
import { resolveMarketingCtaTarget } from '$lib/server/marketing/call-to-action';

// The block editor's live preview: content in, rendered email out. No campaign id -- a draft that has not
// been saved yet still needs to preview. Read-only, so marketing.view is enough, same as the customer-groups
// preview route. Uses a representative sample name and the organization's real business identity, never a
// raw {{token}}, matching the blueprint's "no leaking a placeholder" rule.

const previewSchema = z.object({ content: marketingCampaignContentSchema });

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
	const content = parsed.data.content;
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
		// The signed-in member's own preview: the same authenticated route every other File thumbnail in the
		// app uses, never the public campaign-image route a recipient's mail client fetches from.
		const imageUrls: Record<string, string> = {};
		for (const block of content.blocks) {
			if (block.type === 'image' && block.file_id)
				imageUrls[block.file_id] = `/api/files/${block.file_id}/view`;
		}

		const rendered = await renderCampaignEmail(content, {
			variables: { customer_first_name: 'Alex', business_name: business.name },
			serviceNames,
			imageUrls,
			business,
			unsubscribeUrl: null,
			cta
		});
		return json(rendered, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not render a marketing campaign preview.', error);
		return databaseError();
	}
};
