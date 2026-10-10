import { describe, expect, it } from 'vitest';
import { resolveExperienceProfile, type ExperienceDecision } from './profile';

function decision(
	id: string,
	previous: string | null,
	overrides: Partial<ExperienceDecision> = {}
): ExperienceDecision {
	return {
		id,
		experience_key: 'contractor',
		definition_version: 1,
		business_type_key: 'roofing',
		service_shape: 'Roof repair and replacement',
		package_agreement_id: null,
		source: 'review',
		reason: 'Reviewed services',
		actor_email: 'owner@example.com',
		previous_decision_id: previous,
		decided_at: '2026-10-10T10:00:00.000Z',
		...overrides
	};
}

describe('experience profile', () => {
	it('gives an Organization without a decision no experience, never Contractor by default', () => {
		expect(resolveExperienceProfile([])).toEqual({
			state: 'missing',
			experience: null,
			decision: null
		});
	});

	it('takes the head of the chain as the current profile, even when times are equal', () => {
		const first = decision('a', null, { business_type_key: null });
		const second = decision('b', 'a', { business_type_key: 'roofing' });
		const profile = resolveExperienceProfile([first, second]);
		expect(profile.state).toBe('confirmed');
		expect(profile.experience).toBe('contractor');
		expect(profile.decision?.id).toBe('b');
	});

	it('refuses an experience or version this build does not know', () => {
		for (const unknown of [
			decision('a', null, { experience_key: 'medspa' }),
			decision('a', null, { definition_version: 2 }),
			decision('a', null, { experience_key: 'constructor' })
		]) {
			const profile = resolveExperienceProfile([unknown]);
			expect(profile.state).toBe('unrecognized');
			expect(profile.experience).toBeNull();
		}
	});

	it('refuses a chain with two heads or a fork', () => {
		expect(
			resolveExperienceProfile([decision('a', null), decision('b', null)]).experience
		).toBeNull();
		const fork = resolveExperienceProfile([
			decision('a', null),
			decision('b', 'a'),
			decision('c', 'a')
		]);
		expect(fork.state).toBe('unresolved');
		expect(fork.experience).toBeNull();
	});
});
