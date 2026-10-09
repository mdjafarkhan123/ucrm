import { describe, expect, it } from 'vitest';
import { validateDefinition, type DefinitionLimits } from './definition';
import { AUTOMATION_SCHEMA_VERSION } from '$lib/automation/catalog';

const noLimits: DefinitionLimits = {
	maxConditions: null,
	maxSteps: null,
	maxCustomerMessages: null,
	minMessageSpacingMinutes: null,
	maxDelayDays: null,
	maxEnrollmentDays: null
};
const wait = (unit: 'minutes' | 'hours' | 'days', amount: number) => ({
	type: 'wait',
	key: 'wait.relative_delay',
	config: { unit, amount }
});
const emailConfig = {
	subject: 'Following up on your quote',
	body: 'Hi {{customer_name}}, just checking in — view your quote here: {{quote_link}}'
};

// A valid, activation-ready Quote follow-up: delivered -> wait -> email, stop when the quote no longer waits.
function validInput(overrides: Record<string, unknown> = {}) {
	return {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: { key: 'quote.delivery_succeeded', config: {} },
		conditions: [{ key: 'quote.recipient_attached', config: {} }],
		steps: [
			{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'days', amount: 3 } },
			{ type: 'action', key: 'action.send_email', config: { ...emailConfig } }
		],
		stops: [{ key: 'stop.quote_approved' }, { key: 'stop.customer_reply' }],
		...overrides
	};
}

describe('validateDefinition', () => {
	it('accepts a valid activation-ready recipe and returns a canonical hash and trigger key', () => {
		const result = validateDefinition(validInput(), noLimits, 'activation');
		expect(result.ok).toBe(true);
		if (!result.ok) return;
		expect(result.triggerKey).toBe('quote.delivery_succeeded');
		expect(result.hash).toMatch(/^[0-9a-f]{64}$/);
		expect(result.definition.steps).toHaveLength(2);
	});

	it('accepts a wait measured in minutes and refuses an unknown wait unit', () => {
		const wait = (unit: string) =>
			validInput({
				steps: [
					{ type: 'wait', key: 'wait.relative_delay', config: { unit, amount: 5 } },
					{ type: 'action', key: 'action.send_email', config: { ...emailConfig } }
				]
			});
		expect(validateDefinition(wait('minutes'), noLimits, 'activation').ok).toBe(true);
		expect(validateDefinition(wait('weeks'), noLimits, 'activation').ok).toBe(false);
	});

	it('computes the same hash regardless of the key order the browser sent', () => {
		const a = validateDefinition(
			{
				schema_version: AUTOMATION_SCHEMA_VERSION,
				trigger: { key: 'quote.delivery_succeeded', config: {} },
				conditions: [],
				steps: [{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'days', amount: 3 } }],
				stops: [{ key: 'stop.customer_reply' }]
			},
			noLimits,
			'draft'
		);
		const b = validateDefinition(
			{
				stops: [{ key: 'stop.customer_reply' }],
				steps: [{ config: { amount: 3, unit: 'days' }, key: 'wait.relative_delay', type: 'wait' }],
				conditions: [],
				trigger: { config: {}, key: 'quote.delivery_succeeded' },
				schema_version: AUTOMATION_SCHEMA_VERSION
			},
			noLimits,
			'draft'
		);
		expect(a.ok && b.ok && a.hash === b.hash).toBe(true);
	});

	it('rejects an unknown trigger key', () => {
		const result = validateDefinition(
			validInput({ trigger: { key: 'quote.nope', config: {} } }),
			noLimits,
			'draft'
		);
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.errors.some((e) => e.path === 'trigger')).toBe(true);
	});

	it('rejects a blocked catalog entry (staff notification is not authorable yet)', () => {
		const result = validateDefinition(
			validInput({
				steps: [{ type: 'action', key: 'action.notify_staff', config: { user_ids: ['x'] } }]
			}),
			noLimits,
			'draft'
		);
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.errors.some((e) => e.path === 'steps.0')).toBe(true);
	});

	it('accepts a send-sms step (Stage 7: authorable now)', () => {
		const result = validateDefinition(
			validInput({
				steps: [
					{ type: 'action', key: 'action.send_sms', config: { body: 'Hi {{customer_name}}' } }
				]
			}),
			noLimits,
			'draft'
		);
		expect(result.ok).toBe(true);
	});

	it('rejects unknown config fields via the strict per-entry schema', () => {
		const result = validateDefinition(
			validInput({
				steps: [{ type: 'action', key: 'action.send_email', config: { ...emailConfig, evil: 1 } }]
			}),
			noLimits,
			'draft'
		);
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.errors.some((e) => e.path.startsWith('steps.0.config'))).toBe(true);
	});

	it('rejects a step whose declared type does not match the catalog kind', () => {
		const result = validateDefinition(
			validInput({
				steps: [{ type: 'wait', key: 'action.send_email', config: { ...emailConfig } }]
			}),
			noLimits,
			'draft'
		);
		expect(result.ok).toBe(false);
	});

	it('enforces the structural condition limit', () => {
		const result = validateDefinition(
			validInput({
				conditions: [
					{ key: 'quote.recipient_attached', config: {} },
					{ key: 'quote.current_status', config: { statuses: ['awaiting_response'] } }
				]
			}),
			{ ...noLimits, maxConditions: 1 },
			'draft'
		);
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.errors.some((e) => e.path === 'conditions')).toBe(true);
	});

	it('allows an incomplete draft but blocks activation without steps or stops', () => {
		const partial = {
			schema_version: AUTOMATION_SCHEMA_VERSION,
			trigger: { key: 'quote.delivery_succeeded', config: {} },
			conditions: [],
			steps: [],
			stops: []
		};
		expect(validateDefinition(partial, noLimits, 'draft').ok).toBe(true);
		const activation = validateDefinition(partial, noLimits, 'activation');
		expect(activation.ok).toBe(false);
		if (activation.ok) return;
		expect(activation.errors.some((e) => e.path === 'steps')).toBe(true);
		expect(activation.errors.some((e) => e.path === 'stops')).toBe(true);
	});

	it('collapses duplicate stop conditions', () => {
		const result = validateDefinition(
			validInput({ stops: [{ key: 'stop.customer_reply' }, { key: 'stop.customer_reply' }] }),
			noLimits,
			'activation'
		);
		expect(result.ok).toBe(true);
		if (!result.ok) return;
		expect(result.definition.stops).toHaveLength(1);
	});

	it('rejects the wrong schema version', () => {
		const result = validateDefinition(validInput({ schema_version: 999 }), noLimits, 'draft');
		expect(result.ok).toBe(false);
	});

	describe('website inquiry recipes (Part 4 Stage 6)', () => {
		const inquiry = (overrides: Record<string, unknown> = {}) => ({
			schema_version: AUTOMATION_SCHEMA_VERSION,
			trigger: { key: 'website_inquiry.received', config: {} },
			conditions: [],
			steps: [
				{ type: 'wait', key: 'wait.relative_delay', config: { unit: 'minutes', amount: 5 } },
				{
					type: 'action',
					key: 'action.send_customer_message',
					config: {
						sms_body: 'Hi {{customer_name}}, thanks for contacting {{business_name}}.',
						email_subject: 'Thanks, {{customer_name}}',
						email_body: 'We got your message.'
					}
				}
			],
			stops: [],
			...overrides
		});

		it('accepts the reply step and records the always-on reply stops even when left out', () => {
			const result = validateDefinition(inquiry(), noLimits, 'activation');
			expect(result.ok).toBe(true);
			if (!result.ok) return;
			expect(result.triggerKey).toBe('website_inquiry.received');
			expect(result.definition.stops.map((stop) => stop.key)).toEqual([
				'stop.inquiry_staff_reply',
				'stop.inquiry_customer_reply'
			]);
		});

		it('allows an email-only reply but requires the email copy', () => {
			const step = (config: Record<string, unknown>) =>
				inquiry({ steps: [{ type: 'action', key: 'action.send_customer_message', config }] });
			expect(
				validateDefinition(
					step({ email_subject: 'Hi', email_body: 'Thanks' }),
					noLimits,
					'activation'
				).ok
			).toBe(true);
			expect(validateDefinition(step({ sms_body: 'Thanks' }), noLimits, 'activation').ok).toBe(
				false
			);
		});

		it('refuses quote variables, which have nothing to fill them for an inquiry', () => {
			const result = validateDefinition(
				inquiry({
					steps: [
						{
							type: 'action',
							key: 'action.send_customer_message',
							config: { email_subject: 'Quote {{quote_number}}', email_body: 'See {{quote_link}}' }
						}
					]
				}),
				noLimits,
				'activation'
			);
			expect(result.ok).toBe(false);
		});

		it('refuses quote steps, conditions and stops on an inquiry, and the inquiry step on a quote', () => {
			const emailStep = { type: 'action', key: 'action.send_email', config: { ...emailConfig } };
			for (const overrides of [
				{ steps: [emailStep] },
				{ conditions: [{ key: 'quote.recipient_attached', config: {} }] },
				{ stops: [{ key: 'stop.quote_approved' }] }
			]) {
				expect(validateDefinition(inquiry(overrides), noLimits, 'draft').ok).toBe(false);
			}
			const quoteWithInquiryStep = validInput({ steps: inquiry().steps });
			expect(validateDefinition(quoteWithInquiryStep, noLimits, 'draft').ok).toBe(false);
		});

		it('ships a preset that passes activation as-is', async () => {
			const { getAutomationPreset } = await import('$lib/automation/presets');
			const preset = getAutomationPreset('website_speed_to_lead');
			expect(preset).toBeDefined();
			expect(validateDefinition(preset!.blueprint, noLimits, 'activation').ok).toBe(true);
		});
	});

	describe('platform safety values', () => {
		const email = () => ({ type: 'action', key: 'action.send_email', config: { ...emailConfig } });
		const errorsFor = (steps: unknown[], limits: Partial<DefinitionLimits>) => {
			const result = validateDefinition(validInput({ steps }), { ...noLimits, ...limits }, 'draft');
			return result.ok ? [] : result.errors;
		};

		it('refuses a single wait longer than the longest allowed wait, in any unit', () => {
			expect(errorsFor([wait('days', 90), email()], { maxDelayDays: 90 })).toEqual([]);
			expect(errorsFor([wait('days', 91), email()], { maxDelayDays: 90 })[0]?.path).toBe(
				'steps.0.config.amount'
			);
			expect(errorsFor([wait('hours', 2161), email()], { maxDelayDays: 90 })).toHaveLength(1);
		});

		it('refuses more customer messages than one run may send', () => {
			const five = Array.from({ length: 5 }, () => [wait('days', 1), email()]).flat();
			expect(errorsFor(five, { maxCustomerMessages: 5 })).toEqual([]);
			const six = [...five, wait('days', 1), email()];
			expect(errorsFor(six, { maxCustomerMessages: 5 })[0]?.path).toBe('steps');
		});

		it('refuses two customer messages closer together than the shortest gap', () => {
			expect(
				errorsFor([email(), wait('minutes', 60), email()], { minMessageSpacingMinutes: 60 })
			).toEqual([]);
			// Two short waits in a row add up.
			expect(
				errorsFor([email(), wait('minutes', 30), wait('minutes', 30), email()], {
					minMessageSpacingMinutes: 60
				})
			).toEqual([]);
			const tooClose = errorsFor([email(), wait('minutes', 59), email()], {
				minMessageSpacingMinutes: 60
			});
			expect(tooClose[0]?.path).toBe('steps.2');
			expect(errorsFor([email(), email()], { minMessageSpacingMinutes: 60 })).toHaveLength(1);
		});

		it('refuses waits that add up to more than a run may last', () => {
			const steps = [wait('days', 90), email(), wait('days', 90), email()];
			expect(errorsFor(steps, { maxEnrollmentDays: 180 })).toEqual([]);
			expect(
				errorsFor([...steps, wait('days', 1), email()], { maxEnrollmentDays: 180 })[0]?.path
			).toBe('steps');
		});
	});

	describe('visit reminders', () => {
		const reminder = (config: Record<string, unknown>, body = 'See you {{appointment_when}}.') => ({
			schema_version: AUTOMATION_SCHEMA_VERSION,
			trigger: { key: 'appointment.reminder_due', config },
			conditions: [],
			steps: [
				{
					type: 'action',
					key: 'action.send_appointment_email',
					config: { subject: 'Your visit {{appointment_when}}', body }
				}
			],
			stops: []
		});

		it('accepts the default 1 day before and adds the stops the engine always applies', () => {
			const result = validateDefinition(
				reminder({ mode: 'before', amount: 1, unit: 'days' }),
				noLimits,
				'activation'
			);
			expect(result.ok).toBe(true);
			if (!result.ok) return;
			expect(result.definition.stops.map((stop) => stop.key)).toEqual([
				'stop.appointment_not_ahead',
				'stop.client_reminder_opt_out'
			]);
		});

		it('allows 1 hour to 7 days before, and no more', () => {
			const ok = (config: Record<string, unknown>) =>
				validateDefinition(reminder(config), noLimits, 'activation').ok;
			expect(ok({ mode: 'before', amount: 1, unit: 'hours' })).toBe(true);
			expect(ok({ mode: 'before', amount: 168, unit: 'hours' })).toBe(true);
			expect(ok({ mode: 'before', amount: 7, unit: 'days' })).toBe(true);
			expect(ok({ mode: 'before', amount: 8, unit: 'days' })).toBe(false);
			expect(ok({ mode: 'before', amount: 169, unit: 'hours' })).toBe(false);
			expect(ok({ mode: 'before', amount: 30, unit: 'minutes' })).toBe(false);
			expect(ok({})).toBe(false);
		});

		it('accepts a fixed time of day and refuses an impossible one', () => {
			const ok = (config: Record<string, unknown>) =>
				validateDefinition(reminder(config), noLimits, 'activation').ok;
			expect(ok({ mode: 'fixed_time', days_before: 1, time: '18:00' })).toBe(true);
			expect(ok({ mode: 'fixed_time', days_before: 0, time: '18:00' })).toBe(false);
			expect(ok({ mode: 'fixed_time', days_before: 1, time: '25:00' })).toBe(false);
		});

		it('accepts the ready-made Visit reminder as shipped', async () => {
			const { getAutomationPreset } = await import('$lib/automation/presets');
			const preset = getAutomationPreset('visit_reminder');
			expect(preset).toBeDefined();
			expect(validateDefinition(preset!.blueprint, noLimits, 'activation').ok).toBe(true);
		});

		it('refuses quote values in a reminder, and a reminder step on a quote', () => {
			expect(
				validateDefinition(
					reminder({ mode: 'before', amount: 1, unit: 'days' }, 'Quote {{quote_link}}'),
					noLimits,
					'activation'
				).ok
			).toBe(false);
			const onQuote = validInput({
				steps: [
					{
						type: 'action',
						key: 'action.send_appointment_email',
						config: { subject: 'Hi', body: 'Hi' }
					}
				]
			});
			expect(validateDefinition(onQuote, noLimits, 'activation').ok).toBe(false);
		});
	});
});
