import { describe, expect, it } from 'vitest';
import {
	describeReadiness,
	readinessAreasFor,
	readinessRefusal,
	type ReadinessDecisionFacts
} from './readiness';

const ready: ReadinessDecisionFacts = {
	status: 'ready',
	source: 'review',
	checks: [],
	business_message: null
};

describe('describeReadiness', () => {
	it('closes every area that has no decision, with all its tasks', () => {
		const views = describeReadiness('contractor', {});
		expect(views).toHaveLength(readinessAreasFor('contractor').length);
		for (const view of views) {
			expect(view.state).toBe('not_started');
			expect(view.open).toBe(false);
			expect(view.tasks.length).toBeGreaterThan(0);
		}
	});

	it('lists only the checks still open, with their owners', () => {
		const views = describeReadiness('contractor', {
			customer_messaging: {
				status: 'not_ready',
				source: 'review',
				checks: [
					{ key: 'sender_email_verified', state: 'done' },
					{ key: 'text_number_registered', state: 'open' },
					{ key: 'contact_details_confirmed', state: 'not_applicable' }
				],
				business_message: null
			}
		});
		const messaging = views.find((view) => view.key === 'customer_messaging')!;
		expect(messaging.open).toBe(false);
		expect(messaging.tasks).toEqual([
			expect.objectContaining({ key: 'text_number_registered', owner: 'uplift' })
		]);
	});

	it('counts a check the decision never mentioned as open', () => {
		const views = describeReadiness('contractor', {
			customer_billing: {
				status: 'not_ready',
				source: 'review',
				checks: [{ key: 'documents_reviewed', state: 'done' }],
				business_message: null
			}
		});
		const billing = views.find((view) => view.key === 'customer_billing')!;
		expect(billing.tasks.map((task) => task.key)).toEqual([
			'document_details_confirmed',
			'payment_account_connected'
		]);
	});

	it('opens an area only when its decision is ready', () => {
		const views = describeReadiness('contractor', {
			customer_billing: ready,
			customer_messaging: { ...ready, status: 'held', business_message: 'Paused.' }
		});
		expect(views.find((view) => view.key === 'customer_billing')?.open).toBe(true);
		const held = views.find((view) => view.key === 'customer_messaging')!;
		expect(held.open).toBe(false);
		expect(held.state).toBe('held');
		expect(held.message).toBe('Paused.');
	});

	it('keeps automation closed while messaging is not ready', () => {
		const views = describeReadiness('contractor', { customer_automation: ready });
		const automation = views.find((view) => view.key === 'customer_automation')!;
		expect(automation.open).toBe(false);
		expect(automation.waiting_for.map((area) => area.key)).toEqual(['customer_messaging']);
	});

	it('marks a carried-over decision without claiming it was reviewed', () => {
		const views = describeReadiness('contractor', {
			customer_messaging: { ...ready, source: 'carried_over' }
		});
		const messaging = views.find((view) => view.key === 'customer_messaging')!;
		expect(messaging.open).toBe(true);
		expect(messaging.carried_over).toBe(true);
	});
});

describe('readinessRefusal', () => {
	const view = (decisions: Parameters<typeof describeReadiness>[1], key: string) =>
		describeReadiness('contractor', decisions).find((candidate) => candidate.key === key)!;

	it('names the remaining tasks, their owners and what still works', () => {
		const message = readinessRefusal(
			view(
				{
					customer_messaging: {
						status: 'not_ready',
						source: 'review',
						checks: [
							{ key: 'sender_email_verified', state: 'done' },
							{ key: 'text_number_registered', state: 'open' },
							{ key: 'contact_details_confirmed', state: 'open' }
						],
						business_message: null
					}
				},
				'customer_messaging'
			)
		);
		expect(message).toContain('Email and texts to customers are not open yet');
		expect(message).toContain('Uplift gets your text-message number approved (Uplift)');
		expect(message).toContain(
			'You confirm your business name, phone and address for messages (you)'
		);
		expect(message).toContain('You can still draft messages');
	});

	it('says an unreviewed area has not been reviewed', () => {
		expect(readinessRefusal(view({}, 'customer_billing'))).toContain(
			'Uplift has not reviewed this yet.'
		);
	});

	it('shows the message Uplift wrote for a hold', () => {
		const message = readinessRefusal(
			view(
				{
					customer_billing: {
						...ready,
						status: 'held',
						business_message: 'Waiting on your payment account.'
					}
				},
				'customer_billing'
			)
		);
		expect(message).toContain('Uplift has put this on hold. Waiting on your payment account.');
	});
});
