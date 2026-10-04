import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));
const { buildSetupReturnEmail } = await import('./return-email');

// C3b: the email sent when Uplift sends a section back links straight to it and carries Uplift's note.
describe('buildSetupReturnEmail', () => {
	const base = {
		recipientName: 'Sam Rivera',
		organizationName: 'Bright <Spark>',
		sectionKey: 'business',
		sectionTitle: 'Your business',
		note: 'Use the name on your van.\nAnd add the <b>postcode</b>.',
		questionCount: 2,
		origin: 'https://app.example.com'
	};

	it('links straight to the section and shows the note safely', () => {
		const email = buildSetupReturnEmail(base);
		expect(email.subject).toBe('Uplift needs a change to Your business');
		expect(email.htmlContent).toContain('href="https://app.example.com/setup/business"');
		expect(email.htmlContent).toContain('&lt;b&gt;postcode&lt;/b&gt;');
		expect(email.htmlContent).not.toContain('<Spark>');
		expect(email.textContent).toContain('Hi Sam,');
		expect(email.textContent).toContain('The 2 questions to change are highlighted on the task.');
		expect(email.textContent).toContain(
			'Open Your business: https://app.example.com/setup/business'
		);
	});

	it('words a single question, or none', () => {
		expect(buildSetupReturnEmail({ ...base, questionCount: 1 }).textContent).toContain(
			'The question to change is highlighted on the task.'
		);
		expect(buildSetupReturnEmail({ ...base, questionCount: 0 }).textContent).toContain(
			'Open the task to see what to change.'
		);
	});
});
