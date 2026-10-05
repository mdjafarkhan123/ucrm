import { describe, expect, it } from 'vitest';
import {
	buildLaunchApprovalRequestEmail,
	buildLaunchApprovedEmail,
	createLaunchApprovalToken,
	launchApprovalLinkUrl,
	launchApprovalTokenHash
} from './launch-approval';
import {
	currentLaunchApproval,
	launchApprovalOutcome,
	launchApprovalWording,
	type LaunchApprovalRequest
} from '$lib/setup/launch-approval';

const request = (overrides: Partial<LaunchApprovalRequest> = {}): LaunchApprovalRequest => ({
	id: 'request-1',
	version: 2,
	requested_at: '2026-10-20T09:00:00Z',
	approver_name: 'Sam Lee',
	approver_email: 'sam@example.com',
	link_sent_at: '2026-10-20T09:00:00Z',
	link_expires_at: '2026-11-19T09:00:00Z',
	status: 'open',
	closed_reason: null,
	closed_at: null,
	not_yet_at: null,
	not_yet_by_name: null,
	not_yet_note: null,
	approved_at: null,
	approved_by_name: null,
	approved_by_email: null,
	approval_method: null,
	approval_wording: null,
	recorded_reason: null,
	replaced_at: null,
	...overrides
});

describe('the private launch link', () => {
	it('keeps only a hash, which the same token always gives', () => {
		const { token, tokenHash } = createLaunchApprovalToken();
		expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
		expect(tokenHash).toMatch(/^\\x[0-9a-f]{64}$/);
		expect(tokenHash).not.toContain(token);
		expect(launchApprovalTokenHash(token)).toBe(tokenHash);
		expect(launchApprovalLinkUrl('https://crm.example', token)).toBe(
			`https://crm.example/launch/${token}`
		);
	});

	it('refuses a token of the wrong shape without a database call', () => {
		expect(launchApprovalTokenHash(undefined)).toBeNull();
		expect(launchApprovalTokenHash('short')).toBeNull();
		expect(launchApprovalTokenHash(`${'a'.repeat(42)}!`)).toBeNull();
	});
});

describe('launch approval wording and state', () => {
	it('names the version approved, as the database records it', () => {
		expect(launchApprovalWording(3)).toBe(
			'I approve this website and system to go live, as shown in preview version 3.'
		);
	});

	it('finds the open request or the standing approval, never a replaced or cancelled one', () => {
		const replaced = request({
			id: 'old',
			status: 'approved',
			approved_at: '2026-10-21T09:00:00Z',
			replaced_at: '2026-10-22T09:00:00Z'
		});
		const cancelled = request({
			id: 'cancelled',
			status: 'cancelled',
			closed_at: 'x',
			closed_reason: 'new_release'
		});
		expect(currentLaunchApproval([replaced, cancelled])).toBeNull();
		expect(currentLaunchApproval([request(), replaced])?.id).toBe('request-1');
		expect(launchApprovalOutcome(replaced)).toBe('Approved — replaced by a newer preview');
		expect(launchApprovalOutcome(cancelled)).toBe('Cancelled — a newer preview was released');
		expect(launchApprovalOutcome(request({ not_yet_at: 'x' }))).toBe('Said not yet');
	});
});

describe('launch approval emails', () => {
	it('asks the approver by first name, with the private link and the version', () => {
		const email = buildLaunchApprovalRequestEmail({
			approverName: 'Sam Lee',
			organizationName: 'Raad LTD',
			version: 2,
			url: 'https://crm.example/launch/abc'
		});
		expect(email.subject).toBe("Please approve Raad LTD's system to go live");
		expect(email.textContent).toContain('Hi Sam,');
		expect(email.textContent).toContain('preview version 2');
		expect(email.textContent).toContain('https://crm.example/launch/abc');
	});

	it('gives a receipt with who approved, when, and the exact wording', () => {
		const email = buildLaunchApprovedEmail({
			recipientName: 'Jafar Khan',
			organizationName: 'Raad LTD',
			approvedByName: 'Sam Lee',
			version: 2,
			approvedAt: '2026-10-22T15:00:00Z',
			timeZone: 'UTC',
			origin: 'https://crm.example'
		});
		expect(email.textContent).toContain('Sam Lee approved');
		expect(email.textContent).toContain('22 October 2026');
		expect(email.textContent).toContain(launchApprovalWording(2));
		expect(email.htmlContent).not.toContain('<script');
	});
});
