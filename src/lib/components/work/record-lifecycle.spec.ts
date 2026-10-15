import { describe, expect, it } from 'vitest';
import { recordLifecycle } from './record-lifecycle';

describe('recordLifecycle', () => {
	it('does not invent earlier records or completed stages when a job is opened', () => {
		const steps = recordLifecycle('job', 'Upcoming');
		expect(steps.filter((step) => step.current).map((step) => step.key)).toEqual(['job']);
		expect(
			steps.filter((step) => step.key !== 'job').every((step) => !step.detail && !step.href)
		).toBe(true);
	});
	it('keeps the actual status, including exceptions to a happy path', () => {
		expect(recordLifecycle('quote', 'Declined')[1]).toMatchObject({
			current: true,
			detail: 'Declined'
		});
		expect(recordLifecycle('paid', 'Never received')[4]).toMatchObject({
			current: true,
			detail: 'Never received'
		});
	});
	it('uses only the resolved related link supplied by the page', () => {
		const steps = recordLifecycle('request', 'Converted', {
			quote: { label: 'Quote #42', href: '/quotes/known-id', detail: 'Converted from this request' }
		});
		expect(steps[1]).toMatchObject({ key: 'quote', label: 'Quote #42', href: '/quotes/known-id' });
		expect(steps[1].current).toBeUndefined();
		expect(steps.filter((step) => step.href)).toHaveLength(1);
	});
});
