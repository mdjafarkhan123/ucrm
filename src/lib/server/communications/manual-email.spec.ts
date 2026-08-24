import { describe, expect, it } from 'vitest';
import { renderManualEmailHtml } from './manual-email';

describe('manual email renderer', () => {
	it('escapes browser-supplied markup and preserves line breaks', () => {
		expect(renderManualEmailHtml('Hello <img src=x onerror=alert(1)>\nThanks & bye')).toBe(
			'<p>Hello &lt;img src=x onerror=alert(1)&gt;<br>Thanks &amp; bye</p>'
		);
	});
});
