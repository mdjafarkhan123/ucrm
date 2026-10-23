import { describe, expect, it, vi } from 'vitest';
import { releaseDueNumbers } from './sms-number-release';
import type { CommunicationWorkerClient } from './sms-worker';
import { TwilioProvisioningError } from './twilio';

const PN_SID = 'PN00000000000000000000000000000001';
const access = {
	subaccountSid: 'AC00000000000000000000000000000001',
	authToken: 'token',
	messagingServiceSid: 'MG00000000000000000000000000000001'
};
const due = (overrides: Record<string, unknown> = {}) => ({
	sender_id: 'sender-1',
	organization_id: 'org-1',
	phone_number: '+13613262553',
	provider_phone_number_sid: PN_SID,
	...overrides
});

function setup(options: { rows?: unknown[]; recorded?: string } = {}) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'communication_sms_due_number_releases')
			return { data: options.rows ?? [due()], error: null };
		if (name === 'communication_sms_record_number_released')
			return { data: options.recorded ?? 'released', error: null };
		if (name === 'communication_sms_record_number_provider_released')
			return { data: true, error: null };
		return { data: null, error: { message: `Unexpected RPC ${name}.` } };
	});
	const twilio = {
		findOwnedPhoneNumber: vi.fn(async () => ({
			phoneNumberSid: PN_SID,
			phoneNumber: '+13613262553',
			capabilities: { sms: true, mms: true, voice: true }
		})),
		releasePhoneNumber: vi.fn(async () => {})
	};
	const deps = {
		client: { rpc } as CommunicationWorkerClient,
		twilio,
		subaccount: vi.fn(async () => access)
	};
	const calls = () => rpc.mock.calls.map(([name]) => name);
	return { deps, rpc, twilio, calls };
}

describe('releaseDueNumbers', () => {
	it('records the release first, then lets Twilio go, then marks Twilio done', async () => {
		const t = setup();
		await expect(releaseDueNumbers(t.deps)).resolves.toEqual({ released: 1, kept: 0, failed: 0 });
		expect(t.calls()).toEqual([
			'communication_sms_due_number_releases',
			'communication_sms_record_number_released',
			'communication_sms_record_number_provider_released'
		]);
		expect(t.twilio.releasePhoneNumber).toHaveBeenCalledWith({
			subaccountSid: access.subaccountSid,
			subaccountAuthToken: 'token',
			phoneNumberSid: PN_SID
		});
		expect(t.twilio.findOwnedPhoneNumber).not.toHaveBeenCalled();
	});

	it('keeps a number a top-up paid first and never asks Twilio', async () => {
		const t = setup({ recorded: 'kept' });
		await expect(releaseDueNumbers(t.deps)).resolves.toEqual({ released: 0, kept: 1, failed: 0 });
		expect(t.twilio.releasePhoneNumber).not.toHaveBeenCalled();
		expect(t.calls()).not.toContain('communication_sms_record_number_provider_released');
	});

	it('looks the number up when its Twilio SID is missing', async () => {
		const t = setup({ rows: [due({ provider_phone_number_sid: null })] });
		await releaseDueNumbers(t.deps);
		expect(t.twilio.findOwnedPhoneNumber).toHaveBeenCalledWith(
			expect.objectContaining({ phoneNumber: '+13613262553' })
		);
		expect(t.twilio.releasePhoneNumber).toHaveBeenCalledWith(
			expect.objectContaining({ phoneNumberSid: PN_SID })
		);
	});

	it('counts a number Twilio no longer has as released', async () => {
		const t = setup({ rows: [due({ provider_phone_number_sid: null })] });
		t.twilio.findOwnedPhoneNumber.mockResolvedValueOnce(null as never);
		await expect(releaseDueNumbers(t.deps)).resolves.toEqual({ released: 1, kept: 0, failed: 0 });
		expect(t.twilio.releasePhoneNumber).not.toHaveBeenCalled();
		expect(t.calls()).toContain('communication_sms_record_number_provider_released');
	});

	it('leaves a number due when Twilio fails, and carries on with the next', async () => {
		const t = setup({ rows: [due(), due({ sender_id: 'sender-2' })] });
		t.twilio.releasePhoneNumber.mockRejectedValueOnce(
			new TwilioProvisioningError('Twilio did not return a result.', null, 'twilio_unknown', true)
		);
		const error = vi.spyOn(console, 'error').mockImplementation(() => {});
		await expect(releaseDueNumbers(t.deps)).resolves.toEqual({ released: 1, kept: 0, failed: 1 });
		const confirmed = t.rpc.mock.calls.filter(
			([name]) => name === 'communication_sms_record_number_provider_released'
		);
		expect(confirmed).toEqual([
			['communication_sms_record_number_provider_released', { p_sender_id: 'sender-2' }]
		]);
		error.mockRestore();
	});

	it('does nothing when no number is due', async () => {
		const t = setup({ rows: [] });
		await expect(releaseDueNumbers(t.deps)).resolves.toEqual({ released: 0, kept: 0, failed: 0 });
		expect(t.deps.subaccount).not.toHaveBeenCalled();
	});
});
