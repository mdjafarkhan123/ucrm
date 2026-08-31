// Contractor Settings Part 6C: the browser-safe shape of an authored recipe definition.
//
// This mirrors the server's `definitionInputSchema` (src/lib/server/automation/definition.ts). The builder
// holds one of these in local form state and POSTs/PATCHes it verbatim; the server re-validates it against
// the same catalog, then computes canonical JSON + hash. Nothing here carries code, SQL, URLs, credentials,
// or a precomputed hash — only catalog keys and their typed config values.

import { AUTOMATION_SCHEMA_VERSION } from '$lib/automation/catalog';

export { AUTOMATION_SCHEMA_VERSION };

export type AuthoredEntry = { key: string; config: Record<string, unknown> };
export type AuthoredStep = {
	type: 'action' | 'wait';
	key: string;
	config: Record<string, unknown>;
};
export type AuthoredStop = { key: string };

// `trigger` is nullable only while a from-scratch draft is still being built; a save requires it, and the
// server rejects a missing trigger. Conditions/steps/stops may be empty in a draft.
export type AuthoredDefinition = {
	schema_version: number;
	trigger: AuthoredEntry | null;
	conditions: AuthoredEntry[];
	steps: AuthoredStep[];
	stops: AuthoredStop[];
};

export function emptyAuthoredDefinition(): AuthoredDefinition {
	return {
		schema_version: AUTOMATION_SCHEMA_VERSION,
		trigger: null,
		conditions: [],
		steps: [],
		stops: []
	};
}

// The send-email steps that still lack authored copy. A contractor writes each email's subject and body as
// plain text (6D-3), so the builder blocks the first save until every send-email step has both. The server
// revalidates the same authored config against the catalog + allow-listed variables, so the two cannot drift
// (docs/automation-behavior-contract.md § Builder).
export function sendEmailStepsMissingContent(definition: AuthoredDefinition): number[] {
	const missing: number[] = [];
	definition.steps.forEach((step, index) => {
		if (step.key === 'action.send_email') {
			const subject = typeof step.config?.subject === 'string' ? step.config.subject.trim() : '';
			const body = typeof step.config?.body === 'string' ? step.config.body.trim() : '';
			if (!subject || !body) missing.push(index);
		}
	});
	return missing;
}
