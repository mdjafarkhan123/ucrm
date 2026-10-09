import { describe, expect, it } from 'vitest';
import {
	TEAM_ROLES,
	adjustmentsFor,
	areaForPath,
	canUseJafarPath,
	effectiveTeamAccess,
	roleAccess,
	storedTeamAccessAdjustments,
	teamAccessProblem,
	teammateHomePath,
	type TeamAccess
} from './team-access';

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

	it('lets every teammate change their own photo and see the team’s photos', () => {
		for (const role of TEAM_ROLES) {
			expect(canUseJafarPath({ role }, '/api/jafar/account/photo', 'POST'), role).toBe(true);
			expect(canUseJafarPath({ role }, '/api/jafar/account/photo', 'DELETE'), role).toBe(true);
			expect(canUseJafarPath({ role }, '/api/jafar/photos/owner', 'GET'), role).toBe(true);
			// Only those two addresses: the rest of the account paths stay closed.
			expect(canUseJafarPath({ role }, '/api/jafar/account/photo/x', 'POST'), role).toBe(false);
			expect(canUseJafarPath({ role }, '/api/jafar/account', 'POST'), role).toBe(false);
		}
	});

	it('gives every teammate their own bell (D3a)', () => {
		for (const role of TEAM_ROLES) {
			expect(canUseJafarPath({ role }, '/jafar/notifications', 'GET'), role).toBe(true);
			expect(canUseJafarPath({ role }, '/api/jafar/notifications', 'GET'), role).toBe(true);
			expect(canUseJafarPath({ role }, '/api/jafar/notifications/read', 'POST'), role).toBe(true);
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
			const home = teammateHomePath({ role });
			expect(home.startsWith('/jafar/'), role).toBe(true);
			expect(canUseJafarPath({ role }, home, 'GET'), role).toBe(true);
		}
		expect(teammateHomePath({ role: 'sales' })).toBe('/jafar/leads');
		expect(teammateHomePath({ role: 'support' })).toBe('/jafar/support');
	});
});

describe('individual access (D2)', () => {
	const sales = (access: TeamAccess) => ({ role: 'sales' as const, access });

	it('starts every role with no sensitive actions', () => {
		for (const role of TEAM_ROLES) expect(roleAccess(role).actions).toEqual([]);
	});

	it('applies Jafar’s adjustments on top of the role', () => {
		const access = effectiveTeamAccess('sales', {
			areas: { leads: 'none', onboarding: 'look', applications: 'work' },
			actions: ['payments']
		});
		expect(access).toEqual({
			areas: { applications: 'work', onboarding: 'look' },
			actions: ['payments']
		});
	});

	it('keeps a Lead’s Application picker and linking closed while Applications is off', () => {
		const leadsOnly = {
			role: 'sales' as const,
			access: effectiveTeamAccess('sales', { areas: { applications: 'none' }, actions: [] })
		};
		const candidates = '/api/jafar/leads/lead-id/applications';
		expect(canUseJafarPath(leadsOnly, '/api/jafar/leads/lead-id', 'GET')).toBe(true);
		expect(canUseJafarPath(leadsOnly, candidates, 'GET')).toBe(false);
		expect(canUseJafarPath(leadsOnly, candidates, 'POST')).toBe(false);
		expect(canUseJafarPath(leadsOnly, `${candidates}/application-id`, 'DELETE')).toBe(false);
		// The standard Sales role looks at Applications, so it may link them from a Lead it works.
		expect(canUseJafarPath({ role: 'sales' }, candidates, 'POST')).toBe(true);
	});

	it('drops an action whose area is closed and caps Packages at looking', () => {
		const access = effectiveTeamAccess('sales', {
			areas: { packages: 'work' },
			actions: ['client_accounts', 'packages']
		});
		expect(access.areas.packages).toBe('look');
		expect(access.actions).toEqual(['packages']);
	});

	it('stores only what differs from the role, and reads it back the same', () => {
		const wanted: TeamAccess = {
			areas: { leads: 'work', applications: 'work', support: 'look' },
			actions: ['client_setup']
		};
		const adjustments = adjustmentsFor('sales', wanted);
		expect(adjustments).toEqual({
			areas: { applications: 'work', support: 'look' },
			actions: ['client_setup']
		});
		expect(effectiveTeamAccess('sales', adjustments)).toEqual(wanted);
		expect(adjustmentsFor('sales', roleAccess('sales'))).toEqual({ areas: {}, actions: [] });
	});

	it('keeps a hand-set area across a role change and lets the rest follow the new role', () => {
		const adjustments = { areas: { leads: 'none' as const }, actions: ['payments' as const] };
		expect(effectiveTeamAccess('support', adjustments)).toEqual({
			areas: { support: 'work' },
			actions: []
		});
	});

	it('ignores unknown stored values', () => {
		expect(
			storedTeamAccessAdjustments({ leads: 'none', bogus: 'work', support: 'admin' }, [
				'payments',
				'launch_rockets'
			])
		).toEqual({ areas: { leads: 'none' }, actions: ['payments'] });
		expect(storedTeamAccessAdjustments(null, null)).toEqual({ areas: {}, actions: [] });
	});

	it('explains access that cannot be saved', () => {
		expect(teamAccessProblem({ areas: {}, actions: [] })).toMatch(/at least one area/);
		expect(teamAccessProblem({ areas: { packages: 'work' }, actions: [] })).toMatch(
			/only be opened/
		);
		expect(teamAccessProblem({ areas: { leads: 'work' }, actions: ['payments'] })).toMatch(
			/Applications/
		);
		expect(teamAccessProblem(roleAccess('sales'))).toBeNull();
	});

	it('needs the action itself for a sensitive change, even with Change on the area', () => {
		const changer = sales({ areas: { applications: 'work' }, actions: [] });
		expect(canUseJafarPath(changer, '/api/jafar/prospects/x/mark-reviewed', 'POST')).toBe(true);
		expect(canUseJafarPath(changer, '/api/jafar/prospects/x/confirm-payment', 'POST')).toBe(false);
		expect(canUseJafarPath(changer, '/api/jafar/prospects/x/provision', 'POST')).toBe(false);

		const payer = sales({ areas: { applications: 'look' }, actions: ['payments'] });
		expect(canUseJafarPath(payer, '/api/jafar/prospects/x/confirm-payment', 'POST')).toBe(true);
		expect(canUseJafarPath(payer, '/api/jafar/prospects/x/reverse-payment', 'POST')).toBe(true);
		expect(canUseJafarPath(payer, '/api/jafar/prospects/x/mark-reviewed', 'POST')).toBe(false);
	});

	it('approves who to contact only with that action (B3); anyone working on Leads can record an opt-out', () => {
		const researcher = sales({ areas: { leads: 'work' }, actions: [] });
		expect(canUseJafarPath(researcher, '/api/jafar/leads/review', 'GET')).toBe(true);
		expect(canUseJafarPath(researcher, '/api/jafar/leads/x/approval', 'POST')).toBe(false);
		expect(canUseJafarPath(researcher, '/api/jafar/leads/x/approval/send-back', 'POST')).toBe(
			false
		);
		expect(canUseJafarPath(researcher, '/api/jafar/leads/x/do-not-contact', 'POST')).toBe(true);
		expect(canUseJafarPath(researcher, '/api/jafar/leads/x/do-not-contact/clear', 'POST')).toBe(
			false
		);

		const approver = sales({ areas: { leads: 'work' }, actions: ['approve_outreach'] });
		expect(canUseJafarPath(approver, '/api/jafar/leads/x/approval', 'POST')).toBe(true);
		expect(canUseJafarPath(approver, '/api/jafar/leads/x/do-not-contact/clear', 'POST')).toBe(true);
	});

	it('runs Deals with Leads work; special terms need their action; only Jafar removes a Deal (B4)', () => {
		const looker = sales({ areas: { leads: 'look' }, actions: [] });
		expect(canUseJafarPath(looker, '/jafar/deals', 'GET')).toBe(true);
		expect(canUseJafarPath(looker, '/api/jafar/deals/x', 'PATCH')).toBe(false);

		const worker = sales({ areas: { leads: 'work' }, actions: [] });
		expect(canUseJafarPath(worker, '/api/jafar/deals', 'POST')).toBe(true);
		expect(canUseJafarPath(worker, '/api/jafar/deals/x', 'PATCH')).toBe(true);
		expect(canUseJafarPath(worker, '/api/jafar/deals/x/pricing', 'POST')).toBe(true);
		expect(canUseJafarPath(worker, '/api/jafar/deals/x/lost', 'POST')).toBe(true);
		expect(canUseJafarPath(worker, '/api/jafar/deals/x/reopen', 'POST')).toBe(true);
		expect(canUseJafarPath(worker, '/api/jafar/deals/x/terms', 'PATCH')).toBe(false);
		expect(canUseJafarPath(worker, '/api/jafar/deals/x/remove', 'POST')).toBe(false);

		const agreer = sales({ areas: { leads: 'work' }, actions: ['deal_terms'] });
		expect(canUseJafarPath(agreer, '/api/jafar/deals/x/terms', 'PATCH')).toBe(true);
		expect(canUseJafarPath(agreer, '/api/jafar/deals/x/remove', 'POST')).toBe(false);

		expect(canUseJafarPath(owner, '/api/jafar/deals/x/terms', 'PATCH')).toBe(true);
		expect(canUseJafarPath(owner, '/api/jafar/deals/x/remove', 'POST')).toBe(true);
	});

	it('changes packages only with the packages action', () => {
		const looker = sales({ areas: { packages: 'look' }, actions: [] });
		expect(canUseJafarPath(looker, '/api/jafar/packages/x', 'GET')).toBe(true);
		expect(canUseJafarPath(looker, '/api/jafar/packages/x/publish', 'POST')).toBe(false);
		const editor = sales({ areas: { packages: 'look' }, actions: ['packages'] });
		expect(canUseJafarPath(editor, '/api/jafar/packages/x/publish', 'POST')).toBe(true);
		expect(canUseJafarPath(editor, '/api/jafar/package-offers', 'POST')).toBe(true);
	});

	it('keeps client account controls separate from onboarding work in Organizations', () => {
		const delivery = sales({ areas: { organizations: 'work' }, actions: [] });
		expect(canUseJafarPath(delivery, '/api/jafar/organizations/x/setup/reviews', 'POST')).toBe(
			true
		);
		expect(
			canUseJafarPath(delivery, '/api/jafar/organizations/x/communications/sending-pause', 'POST')
		).toBe(false);
		expect(canUseJafarPath(delivery, '/api/jafar/organizations/x/team/u', 'PATCH')).toBe(false);

		const controller = sales({ areas: { organizations: 'look' }, actions: ['client_accounts'] });
		expect(
			canUseJafarPath(controller, '/api/jafar/organizations/x/communications/sending-pause', 'POST')
		).toBe(true);
		expect(
			canUseJafarPath(controller, '/api/jafar/organizations/x/payments/stripe-connection', 'POST')
		).toBe(true);
		expect(canUseJafarPath(controller, '/api/jafar/organizations/x/setup/reviews', 'POST')).toBe(
			false
		);
	});

	it('keeps the owner’s password-protected powers for Jafar whatever is granted', () => {
		const everything = sales({
			areas: { organizations: 'work', support: 'work' },
			actions: ['client_accounts']
		});
		for (const pathname of [
			'/api/jafar/organizations/x/billing',
			'/api/jafar/organizations/x/closure/start',
			'/api/jafar/organizations/x/closure/restore',
			'/api/jafar/organizations/x/lifecycle',
			'/api/jafar/organizations/x/team/u/administrator-recovery',
			'/api/jafar/organizations/x/communications/sms/refunds',
			'/api/jafar/organizations/x/communications/sms/adjustments',
			'/api/jafar/organizations/x/communications/sms/holds/h/release',
			'/api/jafar/organizations/x/communications/sms/promotional-credits/c/revoke',
			'/api/jafar/organizations/x/communications/sms/credit-topups/r',
			'/api/jafar/support/settings'
		]) {
			expect(canUseJafarPath(everything, pathname, 'POST'), pathname).toBe(false);
			expect(canUseJafarPath(everything, pathname, 'GET'), pathname).toBe(true);
		}
	});

	it('sends a teammate home to their first open area', () => {
		expect(teammateHomePath(sales({ areas: { support: 'look' }, actions: [] }))).toBe(
			'/jafar/support'
		);
	});
});
