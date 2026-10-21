import { describe, expect, it } from 'vitest';
import { splitMarketingVariables } from './campaign-content';

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
