// How long a card has sat where it is, and how worried to look about it. Jobber's rule, kept in one
// place so the card, the chip, and the drawer can never disagree: fresh under an hour, steady up to a
// day, stale after that.
//
// The clock is the browser's. Nothing here crosses a calendar boundary, so the organization's timezone
// does not come into it — this is elapsed time, not a date.

export type Freshness = 'fresh' | 'steady' | 'stale';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

export type StageAge = {
	/** The short chip label: `0h`, `7h`, `21d`. */
	label: string;
	freshness: Freshness;
	/** Said in full, for screen readers and the drawer. */
	description: string;
};

export function stageAge(enteredAt: string, now: number = Date.now()): StageAge {
	const entered = Date.parse(enteredAt);
	// An unparseable or future timestamp should read as brand new rather than as a huge negative age.
	const elapsed = Number.isNaN(entered) ? 0 : Math.max(0, now - entered);

	if (elapsed < HOUR) {
		return { label: '0h', freshness: 'fresh', description: 'In this stage for less than an hour' };
	}

	if (elapsed < DAY) {
		const hours = Math.floor(elapsed / HOUR);
		return {
			label: `${hours}h`,
			freshness: 'steady',
			description: `In this stage for ${hours} ${hours === 1 ? 'hour' : 'hours'}`
		};
	}

	const days = Math.floor(elapsed / DAY);
	return {
		label: `${days}d`,
		freshness: 'stale',
		description: `In this stage for ${days} ${days === 1 ? 'day' : 'days'}`
	};
}
