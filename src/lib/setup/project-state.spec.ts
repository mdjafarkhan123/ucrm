import { describe, expect, it } from 'vitest';
import { projectState, projectView, type ProjectFacts } from './project-state';

const base: ProjectFacts = {
	paid_at: '2026-10-01T09:00:00Z',
	first_sent_at: null,
	sent: null,
	returned_count: 0,
	ready: null,
	preview: null,
	approval: null,
	handover: null,
	today: '2026-10-05'
};
const sent = { number: 1, submitted_at: '2026-10-02T09:00:00Z' };
// Ready recorded on Friday 9 October: business day 1 is Monday 12th, the range 20–23 October.
const ready = {
	submission_number: 1,
	start_date: '2026-10-09',
	target_from: '2026-10-20',
	target_to: '2026-10-23'
};

describe('projectState', () => {
	it('asks for setup until it is sent, then waits on Uplift', () => {
		expect(projectState(base)).toBe('complete_setup');
		expect(projectState({ ...base, sent })).toBe('uplift_reviewing');
	});

	it('is waiting for the client while a task is sent back before Ready', () => {
		expect(projectState({ ...base, sent, returned_count: 2 })).toBe('waiting_for_information');
	});

	it('turns Ready into Building on the first business day after it, not over the weekend', () => {
		const facts = { ...base, sent, first_sent_at: sent.submitted_at, ready };
		expect(projectState({ ...facts, today: '2026-10-09' })).toBe('ready_for_uplift');
		expect(projectState({ ...facts, today: '2026-10-11' })).toBe('ready_for_uplift');
		expect(projectState({ ...facts, today: '2026-10-12' })).toBe('building');
	});

	it('stays on Building when a task is sent back after Ready', () => {
		expect(
			projectState({
				...base,
				sent: { number: 2, submitted_at: '2026-10-13T09:00:00Z' },
				returned_count: 1,
				ready,
				today: '2026-10-14'
			})
		).toBe('building');
	});
});

describe('projectView', () => {
	it('shows payment done with its day, setup current, and leaves out the sent-back detour', () => {
		const view = projectView(base);
		expect(view.steps.map((step) => step.state)).not.toContain('waiting_for_information');
		expect(view.total).toBe(10);
		expect(view.position).toBe(3);
		expect(view.steps[0]).toMatchObject({ state: 'payment_required', status: 'done', on: null });
		expect(view.steps[1]).toMatchObject({ status: 'done', on: base.paid_at });
		expect(view.steps[2]).toMatchObject({ state: 'complete_setup', status: 'current' });
		expect(view.steps.at(-1)).toMatchObject({ state: 'delivered', status: 'upcoming' });
	});

	it('shows the sent-back step only while it is the current one', () => {
		const view = projectView({
			...base,
			sent,
			first_sent_at: sent.submitted_at,
			returned_count: 1
		});
		expect(view.total).toBe(11);
		expect(view.position).toBe(5);
		expect(view.steps[4]).toMatchObject({ state: 'waiting_for_information', status: 'current' });
	});

	it('dates Ready, the build start and the review range once Ready is recorded', () => {
		const view = projectView({
			...base,
			sent,
			first_sent_at: sent.submitted_at,
			ready,
			today: '2026-10-12'
		});
		const step = (state: string) => view.steps.find((each) => each.state === state);
		expect(view.state).toBe('building');
		expect(step('complete_setup')).toMatchObject({ status: 'done', on: sent.submitted_at });
		expect(step('ready_for_uplift')).toMatchObject({ status: 'done', on: '2026-10-09' });
		expect(step('building')).toMatchObject({ status: 'current', on: '2026-10-12' });
		expect(step('ready_for_review')).toMatchObject({
			status: 'upcoming',
			range: { from: '2026-10-20', to: '2026-10-23' }
		});
		expect(view.after_ready).toBeNull();
	});

	it('notes changes sent after Ready, and tasks Uplift sent back on them', () => {
		const later = { number: 2, submitted_at: '2026-10-13T09:00:00Z' };
		const facts = {
			...base,
			sent: later,
			first_sent_at: sent.submitted_at,
			ready,
			today: '2026-10-13'
		};
		expect(projectView(facts).after_ready).toEqual({ kind: 'changes_sent' });
		expect(projectView({ ...facts, returned_count: 2 }).after_ready).toEqual({
			kind: 'returned',
			count: 2
		});
	});

	it('is Ready for your review once Jafar releases a preview, and notes the client sent their notes', () => {
		const facts = {
			...base,
			sent,
			first_sent_at: sent.submitted_at,
			ready,
			preview: { version: 1, released_at: '2026-10-20T10:00:00Z', notes_sent_at: null },
			today: '2026-10-20'
		};
		const view = projectView(facts);
		expect(view.state).toBe('ready_for_review');
		expect(view.steps.find((each) => each.state === 'building')).toMatchObject({ status: 'done' });
		expect(view.steps.find((each) => each.state === 'ready_for_review')).toMatchObject({
			status: 'current',
			on: '2026-10-20T10:00:00Z'
		});
		expect(view.after_ready).toBeNull();
		expect(
			projectView({
				...facts,
				preview: { ...facts.preview, notes_sent_at: '2026-10-21T09:00:00Z' }
			}).after_ready
		).toEqual({ kind: 'notes_sent', at: '2026-10-21T09:00:00Z' });
	});

	it('is Approved — preparing launch once the final approver approves, dated that day', () => {
		const view = projectView({
			...base,
			sent,
			first_sent_at: sent.submitted_at,
			ready,
			preview: { version: 2, released_at: '2026-10-21T10:00:00Z', notes_sent_at: null },
			approval: { version: 2, approved_at: '2026-10-22T15:00:00Z' },
			today: '2026-10-22'
		});
		expect(view.state).toBe('approved');
		expect(view.steps.find((each) => each.state === 'ready_for_review')).toMatchObject({
			status: 'done'
		});
		expect(view.steps.find((each) => each.state === 'approved')).toMatchObject({
			status: 'current',
			on: '2026-10-22T15:00:00Z'
		});
	});

	it('is Live, then Project delivered, each dated the day Uplift marked it', () => {
		const launched = {
			...base,
			sent,
			first_sent_at: sent.submitted_at,
			ready,
			preview: { version: 2, released_at: '2026-10-21T10:00:00Z', notes_sent_at: null },
			approval: { version: 2, approved_at: '2026-10-22T15:00:00Z' },
			today: '2026-10-26'
		};
		const live = projectView({
			...launched,
			handover: { live_at: '2026-10-24T09:00:00Z', delivered_at: null }
		});
		expect(live.state).toBe('live');
		expect(live.steps.find((each) => each.state === 'live')).toMatchObject({
			status: 'current',
			on: '2026-10-24T09:00:00Z'
		});
		expect(live.steps.find((each) => each.state === 'delivered')?.status).toBe('upcoming');

		const delivered = projectView({
			...launched,
			handover: { live_at: '2026-10-24T09:00:00Z', delivered_at: '2026-10-28T09:00:00Z' }
		});
		expect(delivered.state).toBe('delivered');
		expect(delivered.position).toBe(delivered.total);
		expect(delivered.steps.every((each) => each.status !== 'upcoming')).toBe(true);
	});
});
