import { page } from 'vitest/browser';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render } from 'vitest-browser-svelte';
import { QueryClientProvider } from '@tanstack/svelte-query';
import { createQueryClient } from '$lib/query-client';
import ScheduleJobCreate from './ScheduleJobCreate.svelte';
import type { ClientListItem } from '$lib/clients/api';
import type { JobCreateSeed } from '$lib/jobs/createDraft';
import type { AssessmentCreateSeed } from '$lib/requests/assessmentSeed';
import type { NewVisitDraft } from '$lib/schedule/drag';

// The compact "new job" form Schedule opens from empty calendar space. It seeds the day and time from the
// gesture, collects a client, property, title and first-visit schedule, and hands the draft back: Save writes
// it through the Jobs-owned create command on the page, More Options carries it to the full New Job page. See
// the Schedule behaviour contract, "Opening, creating and editing".

const client: ClientListItem = {
	id: 'client-1',
	display_name: 'Colin Reed',
	company_name: null,
	client_type: 'residential',
	lifecycle_status: 'active',
	lead_source: null,
	archived_at: null,
	updated_at: '2026-08-01T00:00:00.000Z',
	primary_property: {
		id: 'prop-1',
		label: 'Home',
		address_line1: '1 Oak St',
		city: 'Austin',
		state_region: 'TX',
		postal_code: '73301'
	},
	additional_property_count: 0,
	email: null,
	phone: null,
	tags: []
};

const timedDraft: NewVisitDraft = {
	visit_date: '2026-09-10',
	start_time: '09:00',
	end_time: '10:00',
	all_day: false
};

function renderForm(
	props: { draft?: NewVisitDraft | null } = {},
	onCreate = vi.fn(),
	onMoreOptions = vi.fn(),
	onCreateRequest = vi.fn(),
	onClose = vi.fn()
) {
	const queryClient = createQueryClient();
	render(
		ScheduleJobCreate,
		{
			props: {
				open: true,
				draft: props.draft ?? timedDraft,
				onCreate,
				onMoreOptions,
				onCreateRequest,
				onClose
			}
		},
		{ wrapper: QueryClientProvider, wrapperProps: { client: queryClient } }
	);
	return { onCreate, onMoreOptions, onCreateRequest, onClose };
}

const originalFetch = globalThis.fetch;

function mockFetch() {
	globalThis.fetch = vi.fn((input: RequestInfo | URL) => {
		const url = String(input);
		if (url.includes('/team/assignable')) {
			return Promise.resolve(new Response(JSON.stringify({ members: [] }), { status: 200 }));
		}
		if (url.includes('/api/clients')) {
			return Promise.resolve(
				new Response(JSON.stringify({ clients: [client], next_cursor: null }), { status: 200 })
			);
		}
		return Promise.resolve(new Response('{}', { status: 200 }));
	});
}

async function pickTheClient() {
	await page.getByRole('combobox', { name: 'Client' }).click();
	await page.getByRole('option', { name: /Colin Reed/ }).click();
}

async function typeTitle() {
	await page.getByLabelText('Job title').fill('Fence repair');
}

describe('ScheduleJobCreate', () => {
	afterEach(() => {
		globalThis.fetch = originalFetch;
	});

	it('opens as "New job" with a "Save job" action', async () => {
		mockFetch();
		renderForm();

		await expect.element(page.getByRole('heading', { name: 'New job' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Save job' })).toBeVisible();
	});

	it('refuses to save without a title', async () => {
		mockFetch();
		const { onCreate } = renderForm();

		await page.getByRole('button', { name: 'Save job' }).click();

		await expect.element(page.getByText('Give the job a title.')).toBeVisible();
		expect(onCreate).not.toHaveBeenCalled();
	});

	it('refuses to save until a client is chosen', async () => {
		mockFetch();
		const { onCreate } = renderForm();

		await typeTitle();
		await page.getByRole('button', { name: 'Save job' }).click();

		await expect.element(page.getByText('Choose a client to continue.')).toBeVisible();
		expect(onCreate).not.toHaveBeenCalled();
	});

	it('hands back the client, property, title and seeded first visit on Save', async () => {
		mockFetch();
		const { onCreate } = renderForm();

		await typeTitle();
		await pickTheClient();
		await page.getByRole('button', { name: 'Save job' }).click();

		await vi.waitFor(() => expect(onCreate).toHaveBeenCalledTimes(1));
		const seed = onCreate.mock.calls[0][0] as JobCreateSeed;
		expect(seed.client?.id).toBe('client-1');
		expect(seed.property_id).toBe('prop-1');
		expect(seed.title).toBe('Fence repair');
		expect(seed.first_visit).toEqual({
			visit_date: '2026-09-10',
			start_time: '09:00',
			end_time: '10:00',
			all_day: false,
			assignee_ids: [],
			instructions: null
		});
	});

	it('hands the draft to More Options without demanding a full form', async () => {
		mockFetch();
		const { onMoreOptions, onCreate } = renderForm();

		await typeTitle();
		await page.getByRole('button', { name: 'More options' }).click();

		await vi.waitFor(() => expect(onMoreOptions).toHaveBeenCalledTimes(1));
		const seed = onMoreOptions.mock.calls[0][0] as JobCreateSeed;
		expect(seed.title).toBe('Fence repair');
		expect(seed.first_visit?.visit_date).toBe('2026-09-10');
		expect(onCreate).not.toHaveBeenCalled();
	});

	it('switches to the Request tab and hands the slot to the New Request page', async () => {
		mockFetch();
		const { onCreateRequest, onCreate } = renderForm();

		await page.getByText('Request', { exact: true }).click();
		// The Request tab is a hand-off, not a form: the job fields and its Save are gone.
		await expect.element(page.getByRole('heading', { name: 'New request' })).toBeVisible();
		await expect.element(page.getByRole('button', { name: 'Save job' })).not.toBeInTheDocument();

		await page.getByRole('button', { name: 'Continue to new request' }).click();

		await vi.waitFor(() => expect(onCreateRequest).toHaveBeenCalledTimes(1));
		const seed = onCreateRequest.mock.calls[0][0] as AssessmentCreateSeed;
		expect(seed).toEqual({
			visit_date: '2026-09-10',
			start_time: '09:00',
			end_time: '10:00',
			all_day: false
		});
		expect(onCreate).not.toHaveBeenCalled();
	});

	it('carries an Anytime slot to the Request page without a clock time', async () => {
		mockFetch();
		const { onCreateRequest } = renderForm({
			draft: { visit_date: '2026-09-12', start_time: null, end_time: null, all_day: true }
		});

		await page.getByText('Request', { exact: true }).click();
		await page.getByRole('button', { name: 'Continue to new request' }).click();

		await vi.waitFor(() => expect(onCreateRequest).toHaveBeenCalledTimes(1));
		const seed = onCreateRequest.mock.calls[0][0] as AssessmentCreateSeed;
		expect(seed).toEqual({
			visit_date: '2026-09-12',
			start_time: null,
			end_time: null,
			all_day: true
		});
	});
});
