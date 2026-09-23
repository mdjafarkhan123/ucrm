import type { MarketingCampaignContent } from '$lib/marketing/campaign-content';
import { sendMarketingEmail, type MarketingEmail } from '$lib/server/communications/ses';
import { hydrateRuleLabels } from '$lib/server/marketing/customer-groups';
import { resolveMarketingCtaTarget } from '$lib/server/marketing/call-to-action';
import {
	appOrigin,
	buildOrganizationMarketingSendContext,
	type OrganizationMarketingSendContext
} from '$lib/server/marketing/dispatcher';
import {
	renderCampaignEmail,
	resolveMarketingVariablesPlainText
} from '$lib/server/marketing/render-email';

// M4 stage 5: a thin, content-only use of the real Marketing send path (blueprint §3 M4) -- no campaign id,
// no allowance/reservation, no recipient row. Renders exactly like preview/+server.ts (sample name, no
// unsubscribe link) but actually submits through the organization's real SES tenant to the requesting
// contractor's own inbox, subject prefixed so it is never mistaken for a live send.

export class MarketingTestSendError extends Error {}

type Dependencies = {
	buildContext?: (organizationId: string) => Promise<OrganizationMarketingSendContext>;
	send?: (message: MarketingEmail) => Promise<{ messageId: string }>;
};

export async function sendTestMarketingEmail(
	organizationId: string,
	recipientEmail: string,
	content: MarketingCampaignContent,
	dependencies: Dependencies = {}
): Promise<{ messageId: string }> {
	const buildContext = dependencies.buildContext ?? buildOrganizationMarketingSendContext;
	const send = dependencies.send ?? sendMarketingEmail;

	let context: OrganizationMarketingSendContext;
	try {
		context = await buildContext(organizationId);
	} catch (error) {
		console.error('Could not build a Marketing test-send context.', error);
		throw new MarketingTestSendError(
			"Marketing sending isn't fully set up yet. Verify the sending domain and add a sender before sending a test email."
		);
	}

	const catalogItemIds = content.blocks
		.filter((block) => block.type === 'service_summary')
		.flatMap((block) => (block.type === 'service_summary' ? block.catalog_item_ids : []));
	const labels = await hydrateRuleLabels(organizationId, catalogItemIds, []);
	const serviceNames = Object.fromEntries(
		labels.catalog_items.map((item) => [item.id, item.label])
	);

	const variables = { customer_first_name: 'Alex', business_name: context.business.name };
	const rendered = await renderCampaignEmail(content, {
		variables,
		serviceNames,
		business: context.business,
		unsubscribeUrl: null,
		// The real target without a recipient token: a test email is not a campaign result.
		cta: content.cta
			? await resolveMarketingCtaTarget(organizationId, content.cta, appOrigin())
			: null
	});
	if (rendered.errors.length > 0)
		throw new MarketingTestSendError(
			`The campaign content could not be rendered: ${rendered.errors[0]?.message ?? 'unknown MJML error'}.`
		);

	return send({
		from: { email: context.fromEmail, name: context.fromName },
		to: { email: recipientEmail },
		replyTo: context.replyTo,
		subject: `[Test] ${resolveMarketingVariablesPlainText(content.subject, variables)}`,
		htmlContent: rendered.html,
		textContent: rendered.text,
		tenantName: context.tenantName,
		configurationSetName: context.configurationSetName,
		headers: []
	});
}
