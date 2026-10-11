// Builds mock Timesheets responses for the screen check: a 15-person week with every state the row can show.
import { writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const days = ['2026-10-11', '2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17'];
const names = [
	'Alejandra Montgomery-Fitzgerald',
	'Ben Carter',
	'Chloe Nguyen',
	'Darnell Washington',
	'Elif Yılmaz',
	'Frank O’Connor',
	'Grace Kim',
	'Hector Ramírez',
	'Isabella Rossi',
	'Jafar Khan',
	'Kwame Mensah',
	'Lena Fischer',
	'Mohammed Al-Rashid',
	'Nora Lindqvist',
	'Oscar Pérez'
];
const now = Date.parse('2026-10-11T16:30:00Z');
const people = names.map((name, index) => {
	const perDay = {};
	let total = 0;
	let count = 0;
	// Sunday off for most; a full week Mon–Fri with some short days.
	for (const [dayIndex, day] of days.entries()) {
		if (dayIndex === 0 && index % 4 !== 0) continue;
		if (dayIndex > 0) continue; // only today has happened yet (Sunday)
		const minutes = 240 + ((index * 37) % 240);
		perDay[day] = minutes;
		total += minutes;
		count += 3;
	}
	return {
		user_id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
		name,
		avatar_url: null,
		status: index === 13 ? 'removed' : index === 7 ? 'deactivated' : 'active',
		is_me: index === 9,
		days: perDay,
		total_minutes: total,
		entry_count: count,
		overlap_count: index === 2 ? 2 : index === 11 ? 1 : 0,
		running:
			index === 1
				? {
						kind: 'visit',
						job_id: '10000000-0000-4000-8000-000000000001',
						job_number: 1042,
						started_at: new Date(now - 47 * 60 * 1000).toISOString(),
						started_on: '2026-10-11',
						long_running: false
					}
				: index === 4
					? {
							kind: 'general',
							job_id: null,
							job_number: null,
							started_at: new Date(now - 14 * 3600 * 1000).toISOString(),
							started_on: '2026-10-11',
							long_running: true
						}
					: null
	};
});

// A past full week (Oct 4–10) for the same people, for a busy grid.
const pastDays = ['2026-10-04', '2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10'];
const pastPeople = people.map((person, index) => {
	const perDay = {};
	let total = 0;
	for (const [dayIndex, day] of pastDays.entries()) {
		if (dayIndex === 0 || dayIndex === 6) continue;
		if ((index + dayIndex) % 9 === 0) continue;
		const minutes = 360 + ((index * 53 + dayIndex * 29) % 210);
		perDay[day] = minutes;
		total += minutes;
	}
	return { ...person, days: perDay, total_minutes: total, entry_count: 18, running: index === 4 ? person.running : null };
});

const base = {
	timezone: 'America/Denver',
	today: '2026-10-11',
	server_now: new Date(now).toISOString(),
	can_view_team: true
};
await writeFile(
	join(here, 'mock-summary-week.json'),
	JSON.stringify({ ...base, span: 'week', from: '2026-10-04', to: '2026-10-10', people: pastPeople })
);
await writeFile(
	join(here, 'mock-summary-today.json'),
	JSON.stringify({ ...base, span: 'week', from: '2026-10-11', to: '2026-10-17', people })
);

const job = (number, title, client) => ({
	id: `10000000-0000-4000-8000-${String(number).padStart(12, '0')}`,
	number,
	visible: true,
	title,
	client_name: client
});
const entries = [];
for (const [dayIndex, day] of pastDays.entries()) {
	if (dayIndex === 0 || dayIndex === 6) continue;
	const at = (h, m) => `${day}T${String(h + 6).padStart(2, '0')}:${String(m).padStart(2, '0')}:00Z`;
	entries.push(
		{ id: `e-${day}-1`, kind: 'general', is_running: false, source: 'timer', started_at: at(7, 30), ended_at: at(8, 15), started_on: day, minutes: 45, notes: 'Loaded the truck at the shop', overlaps: false, long_running: false, job: null, visit_date: null },
		{ id: `e-${day}-2`, kind: 'job', is_running: false, source: 'timer', started_at: at(8, 15), ended_at: at(12, 0), started_on: day, minutes: 225, notes: null, overlaps: dayIndex === 2, long_running: false, job: job(1042, 'Spring cleanup and full mulch refresh for the back garden beds', 'Alejandra Montgomery-Fitzgerald'), visit_date: day },
		{ id: `e-${day}-3`, kind: 'job', is_running: false, source: 'manual', started_at: at(dayIndex === 2 ? 11 : 13, 0), ended_at: at(15, 30), started_on: day, minutes: dayIndex === 2 ? 270 : 150, notes: dayIndex === 3 ? 'Customer asked us to come back Thursday for the side fence' : null, overlaps: dayIndex === 2, long_running: false, job: dayIndex === 4 ? { ...job(988, null, null), visible: false } : job(1077, 'Fence repair', 'Ben Carter'), visit_date: day }
	);
}
await writeFile(
	join(here, 'mock-entries.json'),
	JSON.stringify({ user_id: people[2].user_id, from: '2026-10-04', to: '2026-10-10', timezone: 'America/Denver', server_now: base.server_now, entries, truncated: false })
);
console.log('mocks written');
