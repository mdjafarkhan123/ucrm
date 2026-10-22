import { describe, expect, it } from 'vitest';
import {
	marketingCampaignContentSchema,
	marketingPreviewContentSchema,
	splitMarketingVariables
} from './campaign-content';

describe('splitMarketingVariables', () => {
	it('splits a saved string into text and variable tags, in order', () => {
		expect(splitMarketingVariables('Hi {{customer_first_name}}, from {{business_name}}')).toEqual([
			{ kind: 'text', text: 'Hi ' },
			{ kind: 'variable', variable: 'customer_first_name' },
			{ kind: 'text', text: ', from ' },
			{ kind: 'variable', variable: 'business_name' }
		]);
	});

	it('keeps back-to-back variables apart and reads spaced braces', () => {
		expect(splitMarketingVariables('{{ business_name }}{{customer_first_name}}')).toEqual([
			{ kind: 'variable', variable: 'business_name' },
			{ kind: 'variable', variable: 'customer_first_name' }
		]);
	});

	it('leaves a token the app does not know as plain text', () => {
		expect(splitMarketingVariables('Hello {{nickname}}')).toEqual([
			{ kind: 'text', text: 'Hello {{nickname}}' }
		]);
	});

	it('returns nothing for an empty string', () => {
		expect(splitMarketingVariables('')).toEqual([]);
	});
});

describe('marketingPreviewContentSchema', () => {
	const id = '88888888-8888-8888-8888-888888888888';
	const halfWritten = {
		version: '1',
		subject: 'Hi {{nickname}}',
		blocks: [
			{ id, type: 'heading', level: 'h2', text: '' },
			{ id, type: 'button', label: 'Book', url: 'www.example' },
			{ id, type: 'image', file_id: '', alt: '', link_url: 'javascript:alert(1)' }
		],
		cta: null
	};

	it('accepts a half-written email that saving would refuse', () => {
		expect(marketingCampaignContentSchema.safeParse(halfWritten).success).toBe(false);
		const parsed = marketingPreviewContentSchema.parse(halfWritten);
		expect(parsed.blocks[1]).toMatchObject({ url: '#' });
		expect(parsed.blocks[2]).toMatchObject({ link_url: '#' });
	});

	it('still refuses an unknown key', () => {
		expect(
			marketingPreviewContentSchema.safeParse({ ...halfWritten, extra: true }).success
		).toBe(false);
	});
});
