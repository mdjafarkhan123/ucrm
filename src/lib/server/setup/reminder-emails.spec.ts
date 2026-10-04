import { beforeEach, describe, expect, it, vi } from 'vitest';

const enqueueEmailDelivery = vi.fn();
vi.mock('$lib/server/setup/catalogue', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/setup/catalogue')>(
		'$lib/server/setup/catalogue'
	);
	const { SETUP_CATALOGUE_1 } = await import('$lib/setup/catalogue.fixture');
	return {
		...actual,
		readSetupCatalogue: vi.fn(async () => SETUP_CATALOGUE_1),
		readSetupServiceKeys: vi.fn(async () => new Set<string>()),
		readSetupSectionTitles: vi.fn(
			async () => new Map(SETUP_CATALOGUE_1.sections.map((section) => [section.key, section.title]))
		)
	};
});

vi.mock('$lib/server/events/dispatcher', () => ({
	enqueueEmailDelivery: (...args: unknown[]) => enqueueEmailDelivery(...args)
}));

type Summary = {
	sections: { key: string; title: string; description: string }[];
	progress: { done: number; total: number };
	next: { key: string; title?: string; status?: string; returned?: boolean } | null;
	returned_count: number;
};
let summary: Summary;
vi.mock('$lib/server/setup/client-review', () => ({
	readClientSetupReviews: vi.fn(async () => ({}))
}));
vi.mock('$lib/server/setup/read', () => ({
	readSetupState: vi.fn(async () => ({})),
	setupSummary: () => summary
}));

const { buildSetupReminderEmail, sendDueSetupReminderEmails } = await import('./reminder-emails');
type DueSetupReminder = import('./reminder-emails').DueSetupReminder;

// The database decides when a reminder is due, keeps it to daytime and restarts it on activity (checked against
// the real database); this checks the email points at the right task and that the timer only moves on once
// every email is queued.
const ORIGIN = 'https://app.example.com';
const SERVICES = {
	key: 'services',
	title: 'Services and service area',
	description: 'What you do and where.'
};

function due(overrides: Partial<DueSetupReminder> = {}): DueSetupReminder {
	return {
		organization_id: 'org-1',
		organization_name: 'Bright <Spark>',
		last_activity_at: '2026-10-01T10:00:00+00:00',
		reminders_sent: 0,
		support_waiting: false,
		recipients: [
			{ user_id: 'user-1', email: 'sam@example.com', name: 'Sam Rivera' },
			{ user_id: 'user-2', email: 'alex@example.com', name: null }
		],
		...overrides
	};
}

function client(reminders: DueSetupReminder[]) {
	const rpc = vi.fn(async (name: string) =>
		name === 'due_organization_setup_reminders'
			? { data: reminders, error: null }
			: { data: null, error: null }
	);
	const from = vi.fn(() => {
		const chain = {
			select: () => chain,
			eq: () => chain,
			maybeSingle: async () => ({ data: null, error: null })
		};
		return chain;
	});
	return { rpc, from } as never as Parameters<typeof sendDueSetupReminderEmails>[0] & {
		rpc: typeof rpc;
	};
}

function recorded(db: { rpc: ReturnType<typeof vi.fn> }) {
	return db.rpc.mock.calls
		.filter(([name]) => name === 'record_organization_setup_reminder')
		.map(([, args]) => args);
}

beforeEach(() => {
	enqueueEmailDelivery.mockReset();
	enqueueEmailDelivery.mockResolvedValue('out-1');
	summary = {
		sections: [{ key: 'business', title: 'Your business', description: '' }, SERVICES],
		progress: { done: 1, total: 6 },
		next: { key: 'services' },
		returned_count: 0
	};
});

describe('buildSetupReminderEmail', () => {
	const base = {
		recipientName: 'Sam Rivera',
		organizationName: 'Bright <Spark>',
		task: SERVICES,
		progress: { done: 1, total: 6 },
		origin: ORIGIN
	};

	it('names the next task and links straight to it', () => {
		const email = buildSetupReminderEmail({ ...base, step: 1 });
		expect(email.subject).toBe('Next step for Bright <Spark>: Services and service area');
		expect(email.htmlContent).toContain('Bright &lt;Spark&gt;');
		expect(email.htmlContent).not.toContain('<Spark>');
		expect(email.htmlContent).toContain(`href="${ORIGIN}/setup/services"`);
		expect(email.textContent).toContain('Hi Sam,');
		expect(email.textContent).toContain('1 of 6 tasks are done.');
		expect(email.textContent).toContain(`Continue setup: ${ORIGIN}/setup/services`);
	});

	it('always offers the way to turn reminders off', () => {
		for (const step of [1, 2, 3]) {
			const email = buildSetupReminderEmail({ ...base, step });
			expect(email.htmlContent).toContain(`href="${ORIGIN}/setup#reminder-emails"`);
			expect(email.textContent).toContain(`${ORIGIN}/setup#reminder-emails`);
		}
	});

	it('asks for the change to a section Uplift sent back', () => {
		const email = buildSetupReminderEmail({ ...base, step: 1, kind: 'returned' });
		expect(email.subject).toBe('Uplift needs a change to Services and service area');
		expect(email.textContent).toContain('needs a change to “Services and service area”');
		expect(email.textContent).not.toContain('tasks are done');
		expect(email.textContent).toContain(`Open the task: ${ORIGIN}/setup/services`);
	});

	it('says the third reminder is the last', () => {
		const email = buildSetupReminderEmail({ ...base, step: 3 });
		expect(email.subject).toBe('Last reminder: finish your setup so Uplift can start building');
		expect(email.textContent).toContain('This is our last reminder.');
	});
});

describe('sendDueSetupReminderEmails', () => {
	it('emails each recipient once and moves the timer on', async () => {
		const db = client([due({ reminders_sent: 1 })]);
		expect(await sendDueSetupReminderEmails(db, { origin: ORIGIN })).toBe(1);
		expect(enqueueEmailDelivery).toHaveBeenCalledTimes(2);
		const keys = enqueueEmailDelivery.mock.calls.map(([, email]) => email.idempotencyKey);
		expect(keys).toEqual([
			'setup-reminder:org-1:2026-10-01T10:00:00+00:00:2:user-1',
			'setup-reminder:org-1:2026-10-01T10:00:00+00:00:2:user-2'
		]);
		expect(recorded(db)).toEqual([
			expect.objectContaining({
				target_organization_id: 'org-1',
				seen_last_activity_at: '2026-10-01T10:00:00+00:00',
				outcome: 'sent'
			})
		]);
	});

	it('stops without an email once nothing is left to do', async () => {
		summary.next = null;
		const db = client([due()]);
		expect(await sendDueSetupReminderEmails(db, { origin: ORIGIN })).toBe(0);
		expect(enqueueEmailDelivery).not.toHaveBeenCalled();
		expect(recorded(db)).toEqual([expect.objectContaining({ outcome: 'finished' })]);
	});

	it('points at Check and send once every task is done but setup is not sent', async () => {
		summary.next = {
			key: 'check-and-send',
			title: 'Check and send to Uplift',
			status: 'not_started'
		};
		const db = client([due()]);
		expect(await sendDueSetupReminderEmails(db, { origin: ORIGIN })).toBe(1);
		const [, email] = enqueueEmailDelivery.mock.calls[0];
		expect(JSON.stringify(email)).toContain(`${ORIGIN}/setup/check-and-send`);
	});

	it('points at a section Uplift sent back, worded for it', async () => {
		summary.next = { key: 'services', title: SERVICES.title, status: 'done', returned: true };
		summary.returned_count = 1;
		const db = client([due()]);
		expect(await sendDueSetupReminderEmails(db, { origin: ORIGIN })).toBe(1);
		const [, email] = enqueueEmailDelivery.mock.calls[0];
		expect(email.subject).toBe('Uplift needs a change to Services and service area');
		expect(email.textContent).toContain(`${ORIGIN}/setup/services`);
	});

	it('asks to send the changes once every sent-back section is changed', async () => {
		summary.next = {
			key: 'check-and-send',
			title: 'Check and send to Uplift',
			status: 'not_started'
		};
		summary.returned_count = 1;
		const db = client([due()]);
		await sendDueSetupReminderEmails(db, { origin: ORIGIN });
		const [, email] = enqueueEmailDelivery.mock.calls[0];
		expect(email.subject).toBe('Send your setup changes to Uplift');
		expect(email.textContent).toContain(`Send your changes: ${ORIGIN}/setup/check-and-send`);
	});

	it('waits while a support message of theirs is with Uplift', async () => {
		const db = client([due({ support_waiting: true })]);
		await sendDueSetupReminderEmails(db, { origin: ORIGIN });
		expect(enqueueEmailDelivery).not.toHaveBeenCalled();
		expect(recorded(db)).toEqual([
			expect.objectContaining({ outcome: 'later', look_again_at: expect.any(String) })
		]);
	});

	it('leaves the reminder due when an email could not be queued', async () => {
		enqueueEmailDelivery.mockRejectedValueOnce(new Error('outbox down'));
		const db = client([due()]);
		expect(await sendDueSetupReminderEmails(db, { origin: ORIGIN })).toBe(0);
		expect(recorded(db)).toEqual([]);
	});

	it('still moves the timer on when everyone turned reminders off', async () => {
		const db = client([due({ recipients: [] })]);
		await sendDueSetupReminderEmails(db, { origin: ORIGIN });
		expect(enqueueEmailDelivery).not.toHaveBeenCalled();
		expect(recorded(db)).toEqual([expect.objectContaining({ outcome: 'sent' })]);
	});
});
