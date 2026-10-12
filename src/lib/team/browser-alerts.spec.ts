import { describe, expect, it, vi } from 'vitest';

vi.mock('$app/environment', () => ({ dev: false }));

import { describeThisBrowser } from './browser-alerts';

describe('describeThisBrowser', () => {
	it('names a computer the way a person would', () => {
		expect(
			describeThisBrowser(
				'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
			)
		).toBe('Chrome on Windows');
		expect(
			describeThisBrowser(
				'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36 Edg/130.0'
			)
		).toBe('Edge on Windows');
		expect(
			describeThisBrowser(
				'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
			)
		).toBe('Safari on Mac');
		expect(
			describeThisBrowser(
				'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36'
			)
		).toBe('Chrome on Android');
		expect(
			describeThisBrowser('Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0')
		).toBe('Firefox on Linux');
	});
});
