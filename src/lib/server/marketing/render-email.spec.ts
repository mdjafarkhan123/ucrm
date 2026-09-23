import { describe, expect, it } from 'vitest';
import {
	renderCampaignEmail,
	resolveMarketingVariablesPlainText,
	type MarketingRenderContext
} from './render-email';
import type { MarketingCampaignContent } from '$lib/marketing/campaign-content';

const business: MarketingRenderContext['business'] = {
	name: 'Raad LTD',
	addressLine1: '123 Main St',
	addressLine2: null,
	city: 'Austin',
	region: 'TX',
	postalCode: '78701',
	countryCode: 'US'
};

const baseCtx: MarketingRenderContext = {
	variables: { customer_first_name: 'Alex', business_name: 'Raad LTD' },
	serviceNames: { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa': 'Gutter cleaning' },
	business,
	unsubscribeUrl: 'https://example.com/u/token123',
	cta: null
};

function contentWith(blocks: MarketingCampaignContent['blocks']): MarketingCampaignContent {
	return { version: '1', subject: 'Hi {{customer_first_name}}', blocks, cta: null };
}

describe('renderCampaignEmail', () => {
	it('compiles a heading and text block with no MJML errors', async () => {
		const result = await renderCampaignEmail(
			contentWith([
				{
					id: '11111111-1111-1111-1111-111111111111',
					type: 'heading',
					level: 'h1',
					text: 'Hello {{customer_first_name}}'
				},
				{ id: '22222222-2222-2222-2222-222222222222', type: 'text', text: 'Body copy.' }
			]),
			baseCtx
		);
		expect(result.errors).toEqual([]);
		expect(result.html).toContain('Hello Alex');
		expect(result.text).toContain('HELLO ALEX');
	});

	it('escapes user text so it cannot break out of the compiled markup', async () => {
		const result = await renderCampaignEmail(
			contentWith([
				{
					id: '33333333-3333-3333-3333-333333333333',
					type: 'text',
					text: '</mj-text><mj-raw>injected</mj-raw>'
				}
			]),
			baseCtx
		);
		expect(result.html).not.toContain('<mj-raw>injected</mj-raw>');
		expect(result.html).toContain('&lt;/mj-text&gt;');
	});

	it('leaves an unresolved variable visible instead of blanking it', async () => {
		const result = await renderCampaignEmail(
			contentWith([
				{
					id: '44444444-4444-4444-4444-444444444444',
					type: 'text',
					text: 'Hi {{customer_first_name}}'
				}
			]),
			{ ...baseCtx, variables: {} }
		);
		expect(result.html).toContain('{{customer_first_name}}');
	});

	it('renders a preview-safe placeholder when there is no real unsubscribe link', async () => {
		const result = await renderCampaignEmail(contentWith([]), { ...baseCtx, unsubscribeUrl: null });
		expect(result.html).toContain('only live on a real send');
		expect(result.text).toContain('only live on a real send');
	});

	it('lists resolved service names and skips ids with no known name', async () => {
		const result = await renderCampaignEmail(
			contentWith([
				{
					id: '55555555-5555-5555-5555-555555555555',
					type: 'service_summary',
					title: 'Popular services',
					catalog_item_ids: [
						'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
						'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
					]
				}
			]),
			baseCtx
		);
		expect(result.html).toContain('Gutter cleaning');
		expect(result.html.match(/<li>/g)?.length).toBe(1);
	});

	it('always appends the locked footer with business identity and address', async () => {
		const result = await renderCampaignEmail(contentWith([]), baseCtx);
		expect(result.html).toContain('Raad LTD');
		expect(result.html).toContain('123 Main St');
		expect(result.text).toContain('Raad LTD');
	});

	it('renders the chosen call to action as a button and a plain-text line', async () => {
		const result = await renderCampaignEmail(contentWith([]), {
			...baseCtx,
			cta: { type: 'phone', label: 'Call us', url: 'tel:+15125550100' }
		});
		expect(result.errors).toEqual([]);
		expect(result.html).toContain('href="tel:+15125550100"');
		expect(result.html).toContain('Call us');
		expect(result.text).toContain('Call us: +15125550100');
	});

	it('keeps click tracking off the unsubscribe link', async () => {
		const result = await renderCampaignEmail(contentWith([]), baseCtx);
		expect(result.html).toMatch(/<a ses:no-track[^>]*href="https:\/\/example\.com\/u\/token123"/);
	});
});

describe('resolveMarketingVariablesPlainText', () => {
	it('substitutes without HTML-escaping, for building a real Subject header', () => {
		expect(
			resolveMarketingVariablesPlainText('Hi {{customer_first_name}} & co', {
				customer_first_name: 'A&B'
			})
		).toBe('Hi A&B & co');
	});
});
