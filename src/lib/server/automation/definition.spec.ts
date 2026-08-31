import { describe, expect, it } from 'vitest';
import { validateDefinition, type DefinitionLimits } from './definition';
import { AUTOMATION_SCHEMA_VERSION } from '$lib/automation/catalog';

const noLimits: DefinitionLimits = { maxConditions: null, maxSteps: null };
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

	it('rejects a blocked catalog entry (SMS is not authorable yet)', () => {
		const result = validateDefinition(
			validInput({
				steps: [{ type: 'action', key: 'action.send_sms', config: { body: 'hi' } }]
			}),
			noLimits,
			'draft'
		);
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.errors.some((e) => e.path === 'steps.0')).toBe(true);
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
			{ maxConditions: 1, maxSteps: null },
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
});
