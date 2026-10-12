// Time clock Part 9 — final proof of the plan's success checks on the live dev app (remote dev database,
// Raad LTD), using real logins from Login.md. Usage: ORIGIN=http://localhost:5181 node final-proof.mjs
// It changes data: test visits "Final proof A/B/C" are added to Job #20, a temporary cost rate is given to the
// Field member and a temporary "own hours" override is granted for check 7; both are removed at the end.
// Timers are backdated in SQL only where a real wait would be hours (checks 1, 4, 5); the 8:00-12:00 day is run
// at one minute per hour in real time (check 2).
import { chromium } from '/home/jafar/Ucrm/node_modules/playwright/index.mjs';
import { readFile, writeFile, access } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const origin = process.env.ORIGIN ?? 'http://localhost:5181';
const stateDir = process.env.STATE_DIR ?? '/tmp/claude-1000/-home-jafar-Ucrm/0bc4f674-0157-45ce-bcba-a97b2e9ceeb3/scratchpad';
const env = await readFile('/home/jafar/Ucrm/.env', 'utf8');
const dbUrl = env.match(/^SUPABASE_DB_URL=(.*)$/m)[1];
const login = await readFile('/home/jafar/Ucrm/Login.md', 'utf8');
const creds = {
	owner: login.match(/Contractor owner: `([^`]+)` \/\s*`([^`]+)`/).slice(1),
	field: login.match(/Field member: `([^`]+)` \/\s*`([^`]+)`/).slice(1)
};
const ORG = '18f0d717-904e-48d8-bd99-9df7e3844cda';
const FIELD = '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb';
const OWNER = '1d50477c-8c55-4d33-a550-91ecf637b624';
const JOB = '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e';

// Errors never carry the command line: it holds the database address.
const sql = (query) => {
	try {
		return execFileSync('psql', [dbUrl, '-X', '-At', '-F', '|', '-c', query], {
			encoding: 'utf8',
			stdio: ['ignore', 'pipe', 'pipe']
		}).trim();
	} catch (error) {
		throw new Error(`SQL failed: ${String(error.stderr ?? '').split('\n')[0]}`);
	}
};
const rows = (query) =>
	sql(query)
		.split('\n')
		.filter(Boolean)
		.map((line) => line.split('|'));

const results = [];
function check(name, passed, detail = '') {
	results.push({ name, passed, detail });
	console.log(passed ? 'PASS' : 'FAIL', name, detail);
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const browser = await chromium.launch({ headless: true });

async function session(role, width = 1440) {
	const statePath = join(stateDir, `final-state-${role}.json`);
	try {
		await access(statePath);
	} catch {
		const context = await browser.newContext();
		const page = await context.newPage();
		await page.goto(`${origin}/login`);
		await page.waitForLoadState('networkidle');
		await page.waitForTimeout(1500);
		await page.locator('input[type=email]').fill(creds[role][0]);
		await page.locator('input[type=password]').fill(creds[role][1]);
		await page.getByRole('button', { name: /sign in/i }).click();
		await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 60000 });
		await writeFile(statePath, JSON.stringify(await context.storageState()));
		await context.close();
	}
	const context = await browser.newContext({
		storageState: statePath,
		viewport: { width, height: width < 800 ? 844 : 900 },
		deviceScaleFactor: width < 800 ? 2 : 1
	});
	const page = await context.newPage();
	const call = async (method, path, data) => {
		const response = await page.request.fetch(`${origin}${path}`, {
			method,
			data,
			headers: data === undefined ? {} : { 'content-type': 'application/json' }
		});
		let body = null;
		try {
			body = await response.json();
		} catch {
			/* empty */
		}
		return { status: response.status(), body };
	};
	return { context, page, call };
}

async function shot(page, name) {
	await page.waitForTimeout(800);
	await page.screenshot({ path: join(here, `${name}.png`) });
}

const today = sql(`select (now() at time zone 'Asia/Dhaka')::date`);
const yesterday = sql(`select ((now() at time zone 'Asia/Dhaka')::date - 1)`);
console.log('business today', today, 'yesterday', yesterday);

// --- Setup: clean slate, three visits, a temporary cost rate -------------------------------------------
sql(`delete from running_timers where organization_id='${ORG}' and user_id in ('${FIELD}','${OWNER}')`);
sql(
	`insert into organization_member_cost_profiles (organization_id, user_id, cost_per_hour_minor, updated_by) values ('${ORG}','${FIELD}',3000,'${OWNER}') on conflict (organization_id, user_id) do update set cost_per_hour_minor=3000`
);
const visitIds = {};
for (const name of ['A', 'B', 'C']) {
	visitIds[name] = sql(
		`insert into job_visits (organization_id, job_id, "position", visit_date, title) values ('${ORG}','${JOB}',(select coalesce(max("position"),0)+1 from job_visits where job_id='${JOB}'),'${today}','Final proof ${name}') returning id`
	).split('\n')[0];
}
console.log('visits', visitIds);
const proofStart = sql('select now()');

const field = await session('field', 390);
const owner = await session('owner', 1440);

try {
	// 1. A crew member on a phone starts a timer on today's visit and stops it 40 minutes later ----------
	{
		const start = await field.call('POST', '/api/time-clock/timer', { job_id: JOB, visit_id: visitIds.A });
		check('1 Start on today\'s visit', start.status === 200, `status ${start.status}`);
		sql(`update running_timers set started_at = now() - interval '40 minutes' where user_id='${FIELD}'`);
		const stop = await field.call('POST', '/api/time-clock/timer/stop', undefined);
		check('1 Stop', stop.status === 200, `status ${stop.status}`);
		const entries = rows(
			`select minutes, cost_per_hour_minor, cost_total_minor, source from job_time_entries where visit_id='${visitIds.A}'`
		);
		check(
			'1 Job Labor has one 40-minute entry at their rate',
			entries.length === 1 && entries[0][0] === '40' && entries[0][1] === '3000' && entries[0][2] === '2000',
			JSON.stringify(entries)
		);
		const list = await field.call(
			'GET',
			`/api/time-clock/timesheets/entries?user_id=${FIELD}&from=${today}&to=${today}`
		);
		const mine = (list.body?.entries ?? []).filter((entry) => entry.visit_id === visitIds.A);
		check(
			'1 Their Timesheets day shows the same 40 minutes',
			mine.length === 1 && mine[0].minutes === 40,
			JSON.stringify(mine.map((entry) => entry.minutes))
		);
		// On screen at phone width: Job #20 Labor, then the Timesheets day.
		await field.page.goto(`${origin}/jobs/${JOB}`);
		await field.page.getByText('Final proof A').first().waitFor({ timeout: 30000 }).catch(() => {});
		await field.page.waitForTimeout(2500);
		const labor = field.page.getByRole('heading', { name: /labor/i }).first();
		if (await labor.count()) await labor.scrollIntoViewIfNeeded();
		await shot(field.page, '1-job-labor-390');
		const jobText = await field.page.locator('body').innerText();
		check('1 Job Labor on screen shows 40m', /40m|0:40|40 min/.test(jobText));
		await field.page.goto(`${origin}/timesheets?view=day`);
		await field.page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
		await field.page.waitForTimeout(2500);
		await shot(field.page, '1-timesheets-day-390');
	}

	// 2. Clock in, visit, stop, clock out: contiguous, no overlap (one minute per hour, real time) -------
	{
		const before = sql('select now()');
		const clockIn = await field.call('POST', '/api/time-clock/clock-in', undefined);
		check('2 Clock in', clockIn.status === 200, `status ${clockIn.status}`);
		await sleep(61_000);
		const start = await field.call('POST', '/api/time-clock/timer', { job_id: JOB, visit_id: visitIds.A });
		check('2 Visit starts while clocked in', start.status === 200, `status ${start.status}`);
		await sleep(121_000);
		const stop = await field.call('POST', '/api/time-clock/timer/stop', undefined);
		check('2 Visit stops, day clock resumes', stop.status === 200, `status ${stop.status}`);
		await sleep(61_000);
		const out = await field.call('POST', '/api/time-clock/clock-out', undefined);
		check('2 Clock out', out.status === 200, `status ${out.status}`);
		const parts = rows(
			`select 'general', started_at::text, minutes from general_time_entries where user_id='${FIELD}' and started_at >= '${before}' union all select 'visit', started_at::text, minutes from job_time_entries where user_id='${FIELD}' and started_at >= '${before}' order by 2`
		);
		const general = parts.filter((p) => p[0] === 'general').reduce((sum, p) => sum + Number(p[2]), 0);
		const visit = parts.filter((p) => p[0] === 'visit').reduce((sum, p) => sum + Number(p[2]), 0);
		check(
			'2 Day shows 2 General + 2 Visit = 4 (scaled 1 min per hour), no overlap',
			general === 2 && visit === 2 && parts.length === 3,
			JSON.stringify(parts)
		);
		const week = await field.call(
			'GET',
			`/api/time-clock/timesheets/entries?user_id=${FIELD}&from=${today}&to=${today}`
		);
		const mine = (week.body?.entries ?? []).filter((entry) => entry.started_at >= new Date(before).toISOString());
		check(
			'2 Timesheets flags no overlap on those three entries',
			mine.length === 3 && mine.every((entry) => entry.overlaps === false),
			`${mine.length} entries`
		);
	}

	// 3. Pressing Stop twice, or on two devices, records the hours once ----------------------------------
	{
		const start = await field.call('POST', '/api/time-clock/timer', { job_id: JOB, visit_id: visitIds.B });
		check('3 Start visit B', start.status === 200, `status ${start.status}`);
		sql(`update running_timers set started_at = now() - interval '5 minutes' where user_id='${FIELD}'`);
		const second = await session('field', 390);
		const [one, two] = await Promise.all([
			field.call('POST', '/api/time-clock/timer/stop', undefined),
			second.call('POST', '/api/time-clock/timer/stop', undefined)
		]);
		const third = await field.call('POST', '/api/time-clock/timer/stop', undefined);
		const count = sql(`select count(*) from job_time_entries where visit_id='${visitIds.B}'`);
		check(
			'3 Two devices at once plus a third Stop record the hours once',
			count === '1' && [one, two, third].every((r) => r.status === 200),
			`entries ${count}; statuses ${one.status}/${two.status}/${third.status}`
		);
		await second.context.close();
	}

	// 4. Completing a visit with its timer running stops it, and the hours land once --------------------
	{
		const start = await field.call('POST', '/api/time-clock/timer', { job_id: JOB, visit_id: visitIds.C });
		check('4 Start visit C', start.status === 200, `status ${start.status}`);
		sql(`update running_timers set started_at = now() - interval '7 minutes' where user_id='${FIELD}'`);
		const done = await owner.call('POST', `/api/jobs/${JOB}/visits/${visitIds.C}/complete`, undefined);
		check('4 Visit completed with the timer running', done.status === 200, `status ${done.status}`);
		const running = sql(`select count(*) from running_timers where user_id='${FIELD}'`);
		const entries = rows(`select minutes from job_time_entries where visit_id='${visitIds.C}'`);
		check(
			'4 Timer stopped and the hours landed once',
			running === '0' && entries.length === 1 && entries[0][0] === '7',
			`running ${running}; entries ${JSON.stringify(entries)}`
		);
	}

	// 5. A timer left running overnight: the manager sees the warning, stops it at 5:30 pm the day before -
	let overnightEntry = null;
	{
		const clockIn = await field.call('POST', '/api/time-clock/clock-in', undefined);
		check('5 Field member clocks in', clockIn.status === 200, `status ${clockIn.status}`);
		sql(
			`update running_timers set started_at = (('${yesterday}'::date + time '08:00') at time zone 'Asia/Dhaka') where user_id='${FIELD}'`
		);
		const own = await field.call('POST', '/api/time-clock/timer/stop', undefined);
		check('5 Over 24 hours: their own plain Stop is refused', own.status >= 400, `status ${own.status}`);
		const summary = await owner.call('GET', `/api/time-clock/timesheets?span=day&date=${today}`);
		const person = (summary.body?.people ?? []).find((p) => p.user_id === FIELD);
		check(
			'5 Manager sees the long-running warning',
			Boolean(person?.running?.long_running && person?.running?.over_a_day),
			JSON.stringify(person?.running ?? null)
		);
		await owner.page.goto(`${origin}/timesheets?view=day&date=${today}`);
		await owner.page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
		await owner.page.waitForTimeout(3000);
		await shot(owner.page, '5-manager-warning-1440');
		const stopAt = await owner.call('POST', `/api/time-clock/timesheets/running/${FIELD}/stop`, {
			day: yesterday,
			time: '17:30'
		});
		check('5 Manager stops it at 17:30 the day before', stopAt.status === 200, `status ${stopAt.status}`);
		const entry = rows(
			`select id, started_at::text, minutes from general_time_entries where user_id='${FIELD}' and started_at = (('${yesterday}'::date + time '08:00') at time zone 'Asia/Dhaka')`
		)[0];
		overnightEntry = entry?.[0];
		check('5 Entry is 08:00-17:30 on the starting day (570 min)', entry?.[2] === '570', JSON.stringify(entry));
		const history = await owner.call('GET', `/api/time-clock/timesheets/entries/${overnightEntry}/history`);
		const text = JSON.stringify(history.body);
		check(
			'5 History shows who stopped it',
			history.status === 200 && /Jafar Khan/.test(text),
			text.slice(0, 300)
		);
		await owner.page.goto(`${origin}/timesheets?view=day&date=${yesterday}`);
		await owner.page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
		await owner.page.waitForTimeout(3000);
		const row = owner.page.locator('button[aria-expanded]', { hasText: 'Field Tester' }).first();
		if (await row.count()) await row.click();
		await shot(owner.page, '5-stopped-day-before-1440');
	}

	// 6. A timers-only crew member can start and stop but cannot add or change hours --------------------
	{
		const add = await field.call('POST', '/api/time-clock/timesheets/entries', {
			user_id: FIELD,
			job_id: JOB,
			visit_id: null,
			day: today,
			start_time: '06:00',
			end_time: '06:30',
			notes: null
		});
		const patch = await field.call('PATCH', `/api/time-clock/timesheets/entries/${overnightEntry}`, {
			user_id: FIELD,
			job_id: null,
			visit_id: null,
			day: yesterday,
			start_time: '08:00',
			end_time: '16:00',
			notes: 'timers-only edit'
		});
		const del = await field.call('DELETE', `/api/time-clock/timesheets/entries/${overnightEntry}`, undefined);
		check(
			'6 Timers-only: add, change and delete are refused by /api',
			[add, patch, del].every((r) => r.status === 403),
			`add ${add.status}, change ${patch.status}, delete ${del.status}`
		);
		await field.page.goto(`${origin}/timesheets?view=day&date=${yesterday}`);
		await field.page.getByRole('heading', { name: 'Timesheets' }).first().waitFor({ timeout: 30000 });
		await field.page.waitForTimeout(3000);
		const row = field.page.locator('button[aria-expanded]').first();
		await row.waitFor({ timeout: 30000 });
		if ((await row.getAttribute('aria-expanded')) !== 'true') await row.click();
		await field.page.getByRole('button', { name: 'Entry actions' }).first().waitFor({ timeout: 15000 });
		const addButtons = await field.page.getByRole('button', { name: /add (hours|entry)/i }).count();
		// The header's "Nothing to create yet" popover opens by itself on a phone and covers the page: close it.
		await field.page.keyboard.press('Escape');
		await field.page.getByRole('button', { name: 'Entry actions' }).first().click();
		await field.page.getByRole('menuitem').first().waitFor({ timeout: 5000 });
		const labels = (await field.page.getByRole('menuitem').allInnerTexts()).map((l) => l.trim());
		check(
			'6 On screen: no Add button and the entry menu offers History only',
			addButtons === 0 && labels.length === 1 && /history/i.test(labels[0]),
			`add buttons ${addButtons}; menu ${JSON.stringify(labels)}`
		);
		await shot(field.page, '6-timers-only-menu-390');
		await field.page.keyboard.press('Escape');
	}

	// 7. A manager approves: the crew member can no longer change those entries, the manager still can ---
	{
		const approve = await owner.call('POST', '/api/time-clock/timesheets/approval', {
			cutoff: yesterday,
			user_ids: [FIELD]
		});
		check('7 Manager approves up to the day before', approve.status === 200, JSON.stringify(approve.body).slice(0, 200));
		const approved = sql(`select approved_at is not null from general_time_entries where id='${overnightEntry}'`);
		check('7 The overnight entry is approved', approved === 't', approved);
		// Give the crew member "record my own hours" for this run only, so the approval lock (not the
		// timers-only rung) is what refuses them. Removed in the cleanup below.
		sql(
			`insert into organization_member_permission_overrides (organization_id, user_id, permission_key, override_state) values ('${ORG}','${FIELD}','time.track_own','grant') on conflict (organization_id, user_id, permission_key) do update set override_state='grant'`
		);
		const body = {
			user_id: FIELD,
			job_id: null,
			visit_id: null,
			day: yesterday,
			start_time: '08:00',
			end_time: '17:30'
		};
		const crewPatch = await field.call('PATCH', `/api/time-clock/timesheets/entries/${overnightEntry}`, {
			...body,
			notes: 'crew edit'
		});
		const crewDelete = await field.call('DELETE', `/api/time-clock/timesheets/entries/${overnightEntry}`, undefined);
		check(
			'7 Crew member (own-hours rung) is refused on approved hours (409)',
			crewPatch.status === 409 && crewDelete.status === 409,
			`change ${crewPatch.status}, delete ${crewDelete.status}`
		);
		const managerPatch = await owner.call('PATCH', `/api/time-clock/timesheets/entries/${overnightEntry}`, {
			...body,
			notes: 'Final proof: manager note on approved hours'
		});
		check('7 Manager can still change approved hours', managerPatch.status === 200, `status ${managerPatch.status}`);
		const history = await owner.call('GET', `/api/time-clock/timesheets/entries/${overnightEntry}/history`);
		const text = JSON.stringify(history.body);
		check(
			'7 History records approval and the manager change',
			/approved/i.test(text) && /manager note/i.test(text) && /Jafar Khan/.test(text),
			text.slice(0, 400)
		);
		const stillApproved = sql(`select approved_at is not null from general_time_entries where id='${overnightEntry}'`);
		check('7 The entry stays approved after the manager change', stillApproved === 't', stillApproved);
	}

	// 8. A crew member without "anyone's hours" cannot see or change a teammate's entries ---------------
	{
		const summary = await field.call('GET', `/api/time-clock/timesheets?span=week&date=${today}`);
		const people = summary.body?.people ?? [];
		check(
			'8 Their Timesheets lists only themselves',
			summary.status === 200 && people.length === 1 && people[0].user_id === FIELD && summary.body.can_view_team === false,
			`people ${people.length}; can_view_team ${summary.body?.can_view_team}`
		);
		// The owner records their own half hour so there is a teammate entry to try to reach.
		const added = await owner.call('POST', '/api/time-clock/timesheets/entries', {
			user_id: OWNER,
			job_id: null,
			visit_id: null,
			day: today,
			start_time: '05:00',
			end_time: '05:30',
			notes: 'Final proof owner entry'
		});
		check('8 Setup: the owner adds their own entry', added.status === 200 || added.status === 201, `status ${added.status}`);
		const ownerEntry = sql(
			`select id from general_time_entries where user_id='${OWNER}' and notes='Final proof owner entry' order by created_at desc limit 1`
		);
		const ownerList = await field.call(
			'GET',
			`/api/time-clock/timesheets/entries?user_id=${OWNER}&from=${yesterday}&to=${today}`
		);
		check(
			"8 Reading the owner's entries through /api is refused",
			ownerList.status === 403 || (ownerList.status === 200 && (ownerList.body?.entries ?? []).length === 0),
			`status ${ownerList.status}`
		);
		{
			const change = await field.call('PATCH', `/api/time-clock/timesheets/entries/${ownerEntry}`, {
				user_id: OWNER,
				job_id: null,
				visit_id: null,
				day: today,
				start_time: '05:00',
				end_time: '05:30',
				notes: 'crew edit of a teammate'
			});
			const remove = await field.call('DELETE', `/api/time-clock/timesheets/entries/${ownerEntry}`, undefined);
			const history = await field.call('GET', `/api/time-clock/timesheets/entries/${ownerEntry}/history`);
			check(
				"8 Changing, deleting or reading history of a teammate's entry is refused",
				[change, remove, history].every((r) => r.status >= 400),
				`change ${change.status}, delete ${remove.status}, history ${history.status}`
			);
		}
		const approvalAsCrew = await field.call('POST', '/api/time-clock/timesheets/approval', {
			cutoff: yesterday,
			user_ids: [OWNER]
		});
		check('8 Approving a teammate is refused', approvalAsCrew.status >= 400, `status ${approvalAsCrew.status}`);
	}
} finally {
	// Cleanup: temporary rate and override go; the entries stay as recorded test data.
	sql(`delete from organization_member_permission_overrides where organization_id='${ORG}' and user_id='${FIELD}' and permission_key='time.track_own'`);
	sql(`delete from organization_member_cost_profiles where organization_id='${ORG}' and user_id='${FIELD}'`);
	sql(`delete from running_timers where organization_id='${ORG}' and user_id in ('${FIELD}','${OWNER}')`);
	sql(`delete from general_time_entries where user_id='${OWNER}' and notes='Final proof owner entry'`);
	await browser.close();
	const failed = results.filter((r) => !r.passed);
	await writeFile(join(here, 'final-proof-results.json'), JSON.stringify({ proofStart, results }, null, 2));
	console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
	if (failed.length) console.log('FAILED:', failed.map((f) => f.name).join('; '));
}
