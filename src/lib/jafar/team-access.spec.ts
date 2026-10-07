import { describe, expect, it } from 'vitest';
import { TEAM_ROLES, areaForPath, canUseJafarPath, teammateHomePath } from './team-access';

const owner = { role: null };

describe('Jafar Panel team access', () => {
	it('lets the owner do everything, including paths no area claims', () => {
		expect(canUseJafarPath(owner, '/jafar/settings/team', 'GET')).toBe(true);
		expect(canUseJafarPath(owner, '/api/jafar/team', 'POST')).toBe(true);
		expect(canUseJafarPath(owner, '/api/jafar/support/settings', 'PATCH')).toBe(true);
	});

	it('keeps unclaimed paths for the owner alone', () => {
		for (const role of TEAM_ROLES) {
			for (const pathname of ['/jafar', '/jafar/settings', '/jafar/setup', '/api/jafar/team']) {
				expect(canUseJafarPath({ role }, pathname, 'GET'), `${role} ${pathname}`).toBe(false);
			}
		}
	});

	it('matches whole path segments only', () => {
		expect(areaForPath('/jafar/leads')).toBe('leads');
		expect(areaForPath('/jafar/leads/new')).toBe('leads');
		expect(areaForPath('/jafar/leadsx')).toBeNull();
		expect(areaForPath('/api/jafar/package-offers/1')).toBe('packages');
	});

	it('gives each role its careful start', () => {
		const sales = { role: 'sales' as const };
		expect(canUseJafarPath(sales, '/api/jafar/leads', 'POST')).toBe(true);
		expect(canUseJafarPath(sales, '/api/jafar/prospects', 'GET')).toBe(true);
		expect(canUseJafarPath(sales, '/api/jafar/prospects/x/provision', 'POST')).toBe(false);
		expect(canUseJafarPath(sales, '/api/jafar/support/threads', 'GET')).toBe(false);

		const delivery = { role: 'delivery' as const };
		expect(canUseJafarPath(delivery, '/jafar/onboarding', 'GET')).toBe(true);
		expect(canUseJafarPath(delivery, '/jafar/organizations', 'GET')).toBe(false);

		const support = { role: 'support' as const };
		expect(canUseJafarPath(support, '/api/jafar/support/threads/x/messages', 'POST')).toBe(true);
		expect(canUseJafarPath(support, '/api/jafar/support/settings', 'PATCH')).toBe(false);

		const operations = { role: 'platform_operations' as const };
		expect(canUseJafarPath(operations, '/api/jafar/organizations/x', 'GET')).toBe(true);
		expect(canUseJafarPath(operations, '/api/jafar/organizations/x', 'PATCH')).toBe(false);
		expect(canUseJafarPath(operations, '/api/jafar/packages/x/publish', 'POST')).toBe(false);
		expect(canUseJafarPath(operations, '/api/jafar/operations/x/retry', 'POST')).toBe(false);
	});

	it('sends every role home to a page it can open', () => {
		for (const role of TEAM_ROLES) {
			const home = teammateHomePath(role);
			expect(home.startsWith('/jafar/'), role).toBe(true);
			expect(canUseJafarPath({ role }, home, 'GET'), role).toBe(true);
		}
		expect(teammateHomePath('sales')).toBe('/jafar/leads');
		expect(teammateHomePath('support')).toBe('/jafar/support');
	});
});
