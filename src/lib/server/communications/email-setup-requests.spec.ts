import { describe, expect, it } from 'vitest';
import { deriveEmailSetup } from './email-setup-requests';

const request = (status: string, extra: object = {}) =>
	({
		id: 'r1',
		organization_id: 'o1',
		requested_by: null,
		root_domain: 'acme.com',
		mailbox_provider: 'none',
		note: null,
		status,
		closed_note: null,
		closed_at: null,
		created_at: '2026-09-26T10:00:00Z',
		updated_at: '2026-09-26T10:00:00Z',
		...extra
	}) as never;

describe('deriveEmailSetup', () => {
	it('is none with no request and no domain', () => {
		expect(deriveEmailSetup(null, [])).toEqual({ state: 'none', request: null });
	});

	it('is waiting while the request is open and no sending domain exists', () => {
		expect(deriveEmailSetup(request('open'), []).state).toBe('waiting');
	});

	it('is setting up once Jafar has created a sending domain that is not verified yet', () => {
		const domains = [{ lifecycle_state: 'pending_dns', created_at: '2026-09-26T11:00:00Z' }];
		expect(deriveEmailSetup(request('open'), domains).state).toBe('setting_up');
	});

	it('is setting up when Jafar set a domain up without any request', () => {
		const domains = [{ lifecycle_state: 'pending_dns', created_at: '2026-09-26T11:00:00Z' }];
		expect(deriveEmailSetup(null, domains)).toEqual({ state: 'setting_up', request: null });
	});

	it('is ready with a verified sending domain, whatever the request says', () => {
		const domains = [{ lifecycle_state: 'verified', created_at: '2026-09-26T11:00:00Z' }];
		expect(deriveEmailSetup(request('open'), domains).state).toBe('ready');
		expect(deriveEmailSetup(null, domains).state).toBe('ready');
	});

	it('ignores a removed domain', () => {
		const domains = [{ lifecycle_state: 'removed', created_at: '2026-09-26T11:00:00Z' }];
		expect(deriveEmailSetup(request('open'), domains).state).toBe('waiting');
		expect(deriveEmailSetup(null, domains).state).toBe('none');
	});

	it('shows Jafar’s note for a declined request, then nothing for a cancelled one', () => {
		const declined = deriveEmailSetup(
			request('declined', { closed_note: 'Please call us.', closed_at: '2026-09-26T12:00:00Z' }),
			[]
		);
		expect(declined.state).toBe('declined');
		expect(declined.request?.closed_note).toBe('Please call us.');
		expect(deriveEmailSetup(request('cancelled'), []).state).toBe('none');
	});
});
