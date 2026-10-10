import {
	experienceAwareAccess,
	featureKeysForPermission,
	type CapabilityFamilies,
	type EffectiveOrganizationAccess,
	type ExperienceBasis
} from './effective';
import { contractorNavigation } from './navigation';
import type { AccessChange, AccessDifferences } from '$lib/experience/types';

/**
 * Multi-industry foundation B5: the access an Organization has from its Package alone, set beside the
 * access it has once its Industry experience takes part in the answer. Since B6 the second is the answer the
 * workspace enforces (`resolveOrganizationAccess`); this comparison stays read-only so Uplift can see which
 * loss or gain the experience causes and investigate it.
 *
 * The experience-aware answer follows the plan's intersection rule: a capability stays on only when the
 * Package gives it AND the experience's capability families allow it. A capability whose family is unknown
 * fails closed. Permissions are then narrowed by those capabilities exactly as for the Package.
 */

export type { CapabilityFamilies, ExperienceBasis };
export { experienceAwareAccess };

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
