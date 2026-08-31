// Contractor Settings Part 6C: server-side recipe definition validation and canonicalization.
//
// The browser submits a STRUCTURED definition (trigger/conditions/steps/stops) — never canonical JSON, a
// hash, code, SQL, URLs, or credentials. This module validates it against the same catalog the builder uses
// (src/lib/automation/catalog.ts), enforces structural limits, then computes the canonical JSON and hash
// HERE, on the server, from the validated fields (docs/automation-behavior-contract.md § Recipe definition
// and lifecycle). Consumed by the draft-save and activation commands in 6C-2/6C-3; unit-tested on its own.

import { createHash } from 'node:crypto';
import { z } from 'zod';
import {
	AUTOMATION_SCHEMA_VERSION,
	getCatalogEntry,
	isEnabled,
	type CatalogEntry
} from '$lib/automation/catalog';

// Structural per-recipe limits the save path enforces. Values come from the resolved package/override
// limits; `null` means unlimited. The active-recipes count limit is an activation check, not here.
export type DefinitionLimits = {
	maxConditions: number | null;
	maxSteps: number | null;
};

export type DefinitionMode = 'draft' | 'activation';

// Raw shape accepted from the browser. Strict objects reject unknown keys; config is validated per-entry.
const configRecord = z.record(z.string(), z.unknown());
const entryInput = z.object({ key: z.string().min(1), config: configRecord.default({}) }).strict();
const stepInput = z
	.object({
		type: z.enum(['action', 'wait']),
		key: z.string().min(1),
		config: configRecord.default({})
	})
	.strict();

export const definitionInputSchema = z
	.object({
		schema_version: z.literal(AUTOMATION_SCHEMA_VERSION),
		trigger: entryInput,
		conditions: z.array(entryInput).default([]),
		steps: z.array(stepInput).default([]),
		stops: z.array(z.object({ key: z.string().min(1) }).strict()).default([])
	})
	.strict();

export type DefinitionInput = z.infer<typeof definitionInputSchema>;

export type DefinitionError = { path: string; message: string };

export type CanonicalDefinition = {
	schema_version: number;
	trigger: { key: string; config: Record<string, unknown> };
	conditions: Array<{ key: string; config: Record<string, unknown> }>;
	steps: Array<{ type: 'action' | 'wait'; key: string; config: Record<string, unknown> }>;
	stops: Array<{ key: string }>;
};

export type ValidateResult =
	| {
			ok: true;
			definition: CanonicalDefinition;
			definitionJson: string;
			hash: string;
			triggerKey: string;
	  }
	| { ok: false; errors: DefinitionError[] };

// Deterministic key ordering so an identical recipe always hashes the same, regardless of the order the
// browser sent object keys in. Arrays keep author order (step order is meaningful); only object keys sort.
function canonicalize(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(canonicalize);
	if (value && typeof value === 'object') {
		return Object.fromEntries(
			Object.keys(value as Record<string, unknown>)
				.sort()
				.map((key) => [key, canonicalize((value as Record<string, unknown>)[key])])
		);
	}
	return value;
}

function validateConfig(
	entry: CatalogEntry,
	config: Record<string, unknown>,
	path: string,
	errors: DefinitionError[]
): Record<string, unknown> {
	const parsed = entry.configSchema.safeParse(config);
	if (!parsed.success) {
		for (const issue of parsed.error.issues) {
			const field = issue.path.length ? `${path}.config.${issue.path.join('.')}` : `${path}.config`;
			errors.push({ path: field, message: issue.message });
		}
		return config;
	}
	return parsed.data as Record<string, unknown>;
}

function resolveEntry(
	key: string,
	kind: CatalogEntry['kind'] | CatalogEntry['kind'][],
	path: string,
	errors: DefinitionError[]
): CatalogEntry | null {
	const entry = getCatalogEntry(key);
	const kinds = Array.isArray(kind) ? kind : [kind];
	if (!entry || !kinds.includes(entry.kind)) {
		errors.push({ path, message: 'This building block is not available.' });
		return null;
	}
	if (!isEnabled(entry)) {
		const reason = entry.availability.status === 'blocked' ? entry.availability.reason : '';
		errors.push({ path, message: reason || 'This building block is not available yet.' });
		return null;
	}
	return entry;
}

// Validate a submitted definition against the catalog and limits, and (on success) produce its canonical
// JSON and hash. `draft` allows an incomplete sequence; `activation` additionally requires at least one
// step and one stop. Structural count limits are enforced in both modes.
export function validateDefinition(
	raw: unknown,
	limits: DefinitionLimits,
	mode: DefinitionMode
): ValidateResult {
	const parsed = definitionInputSchema.safeParse(raw);
	if (!parsed.success) {
		return {
			ok: false,
			errors: parsed.error.issues.map((issue) => ({
				path: issue.path.join('.') || 'definition',
				message: issue.message
			}))
		};
	}
	const input = parsed.data;
	const errors: DefinitionError[] = [];

	// Trigger: exactly one, must be an enabled catalog trigger with valid config.
	const triggerEntry = resolveEntry(input.trigger.key, 'trigger', 'trigger', errors);
	const triggerConfig = triggerEntry
		? validateConfig(triggerEntry, input.trigger.config, 'trigger', errors)
		: input.trigger.config;

	// Conditions: 0..limit, each an enabled catalog condition with valid config.
	if (limits.maxConditions !== null && input.conditions.length > limits.maxConditions) {
		errors.push({
			path: 'conditions',
			message: `Use at most ${limits.maxConditions} condition${limits.maxConditions === 1 ? '' : 's'}.`
		});
	}
	const conditions = input.conditions.map((condition, index) => {
		const path = `conditions.${index}`;
		const entry = resolveEntry(condition.key, 'condition', path, errors);
		return {
			key: condition.key,
			config: entry ? validateConfig(entry, condition.config, path, errors) : condition.config
		};
	});

	// Steps: ordered actions/waits, 0..limit, each enabled and matching its declared type.
	if (limits.maxSteps !== null && input.steps.length > limits.maxSteps) {
		errors.push({
			path: 'steps',
			message: `Use at most ${limits.maxSteps} step${limits.maxSteps === 1 ? '' : 's'}.`
		});
	}
	const steps = input.steps.map((step, index) => {
		const path = `steps.${index}`;
		const entry = resolveEntry(step.key, step.type, path, errors);
		return {
			type: step.type,
			key: step.key,
			config: entry ? validateConfig(entry, step.config, path, errors) : step.config
		};
	});

	// Stops: each an enabled catalog stop. Duplicates are collapsed so the same outcome is not listed twice.
	const seenStops = new Set<string>();
	const stops: Array<{ key: string }> = [];
	input.stops.forEach((stop, index) => {
		const entry = resolveEntry(stop.key, 'stop', `stops.${index}`, errors);
		if (entry && !seenStops.has(stop.key)) {
			seenStops.add(stop.key);
			stops.push({ key: stop.key });
		}
	});

	if (mode === 'activation') {
		if (steps.length === 0)
			errors.push({ path: 'steps', message: 'Add at least one step before activating.' });
		if (stops.length === 0)
			errors.push({ path: 'stops', message: 'Add at least one stop condition before activating.' });
	}

	if (errors.length > 0) return { ok: false, errors };

	const definition: CanonicalDefinition = {
		schema_version: input.schema_version,
		trigger: { key: input.trigger.key, config: triggerConfig },
		conditions,
		steps,
		stops
	};
	const definitionJson = JSON.stringify(canonicalize(definition));
	const hash = createHash('sha256').update(definitionJson).digest('hex');

	return { ok: true, definition, definitionJson, hash, triggerKey: input.trigger.key };
}
