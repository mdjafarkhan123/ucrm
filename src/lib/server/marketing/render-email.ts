import mjml2html from 'mjml';
import type {
	MarketingBlock,
	MarketingCampaignContent,
	MarketingVariable
} from '$lib/marketing/campaign-content';

// Turns a validated campaign content document into an actual email. Block content is written by an
// authenticated organization member (marketing.draft), not the public, but it still becomes part of an MJML
// *source string* that gets compiled -- unescaped text could inject stray markup into the compiled email, so
// every user-supplied string is HTML-escaped before it is interpolated here.
//
// MJML (not a hand-rolled table layout, and not React Email, which assumes a JSX toolchain this SvelteKit
// backend does not have) is the established, cross-client-safe way to turn structured content into email
// HTML -- see docs/research note in the M3 planning conversation for the comparison.
//
// The footer (business identity, address, unsubscribe) is owned entirely by this module and is never part
// of the stored content: nothing upstream can remove or edit it.

export type MarketingBusinessIdentity = {
	name: string;
	addressLine1: string;
	addressLine2: string | null;
	city: string;
	region: string | null;
	postalCode: string | null;
	countryCode: string;
};

export type MarketingRenderContext = {
	// Sample or real per-recipient values for the approved merge fields. A variable with no entry here is
	// left as its literal `{{token}}` in the output -- Zod already refuses an unknown token at save time, so
	// this only happens if a caller forgets to supply one of the known variables, and leaving it visible is
	// safer than silently blanking it.
	variables: Partial<Record<MarketingVariable, string>>;
	// catalog_item_id -> current name, prefetched by the caller for whichever ids appear in service_summary
	// blocks. Keeps this module a pure function with no database access of its own.
	serviceNames: Record<string, string>;
	business: MarketingBusinessIdentity;
	// null renders a clearly-inert placeholder instead of a working link -- used for the editor's live
	// preview, where there is no real recipient to bind an unsubscribe token to.
	unsubscribeUrl: string | null;
};

export type MarketingRenderedEmail = {
	html: string;
	text: string;
	errors: { message: string; formattedMessage?: string }[];
};

function escapeHtml(value: string): string {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

const VARIABLE_PATTERN = /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g;

/** Plain-text substitution, for building the real Subject header outside of any HTML context. */
export function resolveMarketingVariablesPlainText(
	text: string,
	variables: Partial<Record<MarketingVariable, string>>
): string {
	return text.replace(
		VARIABLE_PATTERN,
		(match, name: string) => variables[name as MarketingVariable] ?? match
	);
}

function resolveVariablesHtml(
	text: string,
	variables: Partial<Record<MarketingVariable, string>>
): string {
	return escapeHtml(text).replace(VARIABLE_PATTERN, (match, name: string) => {
		const value = variables[name as MarketingVariable];
		return value !== undefined ? escapeHtml(value) : match;
	});
}

function renderBlockMjml(block: MarketingBlock, ctx: MarketingRenderContext): string {
	switch (block.type) {
		case 'heading': {
			const fontSize = block.level === 'h1' ? '28px' : '22px';
			return `<mj-text font-size="${fontSize}" font-weight="700" padding="16px 24px 8px">${resolveVariablesHtml(block.text, ctx.variables)}</mj-text>`;
		}
		case 'text': {
			const paragraphs = block.text
				.split(/\n{2,}/)
				.map(
					(paragraph) =>
						`<p style="margin:0 0 12px">${resolveVariablesHtml(paragraph, ctx.variables).replace(/\n/g, '<br/>')}</p>`
				)
				.join('');
			return `<mj-text padding="8px 24px">${paragraphs}</mj-text>`;
		}
		case 'button':
			return `<mj-button href="${escapeHtml(block.url)}" padding="16px 24px" background-color="#2563eb">${resolveVariablesHtml(block.label, ctx.variables)}</mj-button>`;
		case 'image':
			return `<mj-image src="${escapeHtml(block.url)}" alt="${escapeHtml(block.alt)}"${
				block.link_url ? ` href="${escapeHtml(block.link_url)}"` : ''
			} padding="8px 24px" />`;
		case 'divider':
			return `<mj-divider border-color="#e5e7eb" padding="8px 24px" />`;
		case 'service_summary': {
			const items = block.catalog_item_ids
				.map((id) => ctx.serviceNames[id])
				.filter((name): name is string => Boolean(name));
			const list =
				items.length > 0
					? `<ul style="margin:8px 0 0;padding-left:20px">${items.map((name) => `<li>${escapeHtml(name)}</li>`).join('')}</ul>`
					: `<p style="margin:8px 0 0;color:#6b7280">No services selected yet.</p>`;
			return `<mj-text padding="8px 24px"><strong>${escapeHtml(block.title)}</strong>${list}</mj-text>`;
		}
	}
}

function renderBlockText(block: MarketingBlock, ctx: MarketingRenderContext): string {
	switch (block.type) {
		case 'heading':
			return resolveMarketingVariablesPlainText(block.text, ctx.variables).toUpperCase();
		case 'text':
			return resolveMarketingVariablesPlainText(block.text, ctx.variables);
		case 'button':
			return `${resolveMarketingVariablesPlainText(block.label, ctx.variables)}: ${block.url}`;
		case 'image':
			return block.link_url ? block.link_url : '';
		case 'divider':
			return '---';
		case 'service_summary': {
			const items = block.catalog_item_ids
				.map((id) => ctx.serviceNames[id])
				.filter((name): name is string => Boolean(name));
			return [block.title, ...items.map((name) => `- ${name}`)].join('\n');
		}
	}
}

function footerAddressLines(business: MarketingBusinessIdentity): string[] {
	return [
		business.addressLine1,
		business.addressLine2,
		[business.city, business.region, business.postalCode].filter(Boolean).join(', '),
		business.countryCode
	].filter((line): line is string => Boolean(line && line.trim().length > 0));
}

function renderFooterMjml(ctx: MarketingRenderContext): string {
	const addressLines = footerAddressLines(ctx.business);
	const unsubscribeHtml = ctx.unsubscribeUrl
		? `<a href="${escapeHtml(ctx.unsubscribeUrl)}" style="color:#6b7280">Unsubscribe</a>`
		: `<span style="color:#9ca3af">Unsubscribe (this link is only live on a real send)</span>`;

	return `<mj-section padding="24px" background-color="#f9fafb">
		<mj-column>
			<mj-text align="center" font-size="12px" color="#6b7280" line-height="18px">
				${escapeHtml(ctx.business.name)}<br/>
				${addressLines.map(escapeHtml).join('<br/>')}
			</mj-text>
			<mj-text align="center" font-size="12px" padding-top="8px">${unsubscribeHtml}</mj-text>
		</mj-column>
	</mj-section>`;
}

function renderFooterText(ctx: MarketingRenderContext): string {
	const addressLines = footerAddressLines(ctx.business);
	const unsubscribeLine = ctx.unsubscribeUrl
		? `Unsubscribe: ${ctx.unsubscribeUrl}`
		: 'Unsubscribe (this link is only live on a real send)';
	return [ctx.business.name, ...addressLines, unsubscribeLine].join('\n');
}

export async function renderCampaignEmail(
	content: MarketingCampaignContent,
	ctx: MarketingRenderContext
): Promise<MarketingRenderedEmail> {
	const previewText = content.preview_text
		? resolveVariablesHtml(content.preview_text, ctx.variables)
		: '';

	const mjmlSource = `<mjml>
		<mj-head>
			<mj-title>${resolveVariablesHtml(content.subject, ctx.variables)}</mj-title>
			${previewText ? `<mj-preview>${previewText}</mj-preview>` : ''}
			<mj-attributes>
				<mj-all font-family="Helvetica, Arial, sans-serif" />
				<mj-text color="#111827" line-height="24px" font-size="15px" />
			</mj-attributes>
		</mj-head>
		<mj-body background-color="#ffffff">
			<mj-section padding="24px 0 0">
				<mj-column>
					${content.blocks.map((block) => renderBlockMjml(block, ctx)).join('\n')}
				</mj-column>
			</mj-section>
			${renderFooterMjml(ctx)}
		</mj-body>
	</mjml>`;

	const { html, errors } = await mjml2html(mjmlSource, { validationLevel: 'strict' });

	const text = [
		...content.blocks.map((block) => renderBlockText(block, ctx)),
		'',
		renderFooterText(ctx)
	].join('\n\n');

	return { html, text, errors };
}
