import {
	featureKeysForPermission,
	permissionIsEnabled,
	type EffectiveOrganizationAccess,
	type PermissionScope
} from './effective';
import { contractorNavigation } from './navigation';
import type { AccessChange, AccessDifferences } from '$lib/experience/types';

/**
 * Multi-industry foundation B5: the access an Organization would have once its Industry experience takes
 * part in the answer, set beside the access it has today. Nothing here changes who can do what -- the
 * comparison is read-only and runs before any switch -- so Uplift can see a loss or gain and investigate it
 * while the Organization stays on its current path.
 *
 * The experience-aware answer follows the plan's intersection rule: a capability stays on only when the
 * Package gives it (today's answer) AND the experience's capability families allow it. A capability whose
 * family is unknown fails closed. Permissions are then narrowed by those capabilities exactly as today.
 */

export type ExperienceBasis = {
	/** `confirmed` is the reviewed profile; `planned` is the one experience the agreed edition is sold to. */
	kind: 'confirmed' | 'planned';
	experience: string;
	definition_version: number;
	/** The capability families the definition makes eligible. */
	families: string[];
};

export type CapabilityFamilies = ReadonlyMap<string, string>;

export function experienceAwareAccess(
	legacy: EffectiveOrganizationAccess,
	basis: ExperienceBasis,
	capabilityFamilies: CapabilityFamilies
): EffectiveOrganizationAccess {
	const eligible = new Set(basis.families);
	const features = Object.fromEntries(
		Object.entries(legacy.features).map(([key, on]) => {
			const family = capabilityFamilies.get(key);
			return [key, on && family !== undefined && eligible.has(family)];
		})
	);

	const permissions: Record<string, boolean> = {};
	const permission_scopes: Record<string, PermissionScope> = {};
	for (const [key, granted] of Object.entries(legacy.permissions)) {
		const kept = granted && permissionIsEnabled(key, features);
		permissions[key] = kept;
		if (kept && key in legacy.permission_scopes)
			permission_scopes[key] = legacy.permission_scopes[key];
	}
	return { ...legacy, features, permissions, permission_scopes };
}

function featureCause(key: string, basis: ExperienceBasis, capabilityFamilies: CapabilityFamilies) {
	const family = capabilityFamilies.get(key);
	if (family === undefined)
		return 'This capability has no family, so the experience cannot allow it.';
	return `The ${basis.experience} experience does not allow the ${family} family.`;
}

function changes(
	before: Record<string, boolean>,
	after: Record<string, boolean>,
	cause: (key: string, direction: AccessChange['direction']) => string
): AccessChange[] {
	return [...new Set([...Object.keys(before), ...Object.keys(after)])]
		.filter((key) => (before[key] === true) !== (after[key] === true))
		.sort()
		.map((key) => {
			const direction = after[key] === true ? 'gained' : 'lost';
			return { key, direction, cause: cause(key, direction) };
		});
}

export function compareAccess(
	legacy: EffectiveOrganizationAccess,
	aware: EffectiveOrganizationAccess,
	basis: ExperienceBasis,
	capabilityFamilies: CapabilityFamilies
): AccessDifferences {
	return {
		features: changes(legacy.features, aware.features, (key, direction) =>
			direction === 'lost'
				? featureCause(key, basis, capabilityFamilies)
				: 'The experience-aware answer allows this but today’s does not. This should not happen.'
		),
		permissions: changes(legacy.permissions, aware.permissions, (key, direction) => {
			if (direction === 'gained')
				return 'The experience-aware answer allows this but today’s does not. This should not happen.';
			const lostFeatures = featureKeysForPermission(key).filter(
				(feature) => legacy.features[feature] === true && aware.features[feature] !== true
			);
			return lostFeatures.length
				? `Rides on ${lostFeatures.join(' and ')}, which the experience does not allow.`
				: 'Lost for a reason Uplift cannot explain. Investigate before switching.';
		}),
		navigation: changes(
			{ ...contractorNavigation(legacy) },
			{ ...contractorNavigation(aware) },
			(_key, direction) =>
				direction === 'lost'
					? 'The menu item follows the access above.'
					: 'The menu item would appear without a matching permission. This should not happen.'
		)
	};
}

export const hasDifferences = (differences: AccessDifferences) =>
	differences.features.length + differences.permissions.length + differences.navigation.length > 0;
