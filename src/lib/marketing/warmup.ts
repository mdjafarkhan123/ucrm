// A new Marketing sending domain earns higher daily limits step by step (M6f, HighLevel's ramp-up pattern).
// The database decides; this turns its answer into the plain words the Overview card shows.

export type MarketingWarmupProgress =
	| { status: 'no_domain' }
	| {
			status: 'graduated';
			step: number;
			total_steps: number;
			daily_limit: number | null;
			sent_today: number;
	  }
	| {
			status: 'warming';
			step: number;
			total_steps: number;
			daily_limit: number;
			limit_overridden: boolean;
			sent_today: number;
			next_daily_limit: number | null;
			step_started_at: string;
			days_remaining: number;
			sends_in_step: number;
			sends_needed: number;
			quality_ok: boolean;
	  };

export type WarmupRequirement = { key: 'days' | 'sends' | 'quality'; met: boolean; label: string };

export type WarmupCard = {
	graduated: boolean;
	headline: string;
	stepLabel: string;
	step: number;
	totalSteps: number;
	// null when there is no daily cap to measure against.
	today: { sent: number; limit: number; fraction: number; label: string } | null;
	unlockTitle: string | null;
	requirements: WarmupRequirement[];
	note: string | null;
};

const count = new Intl.NumberFormat('en-US');
const plural = (n: number, one: string, many: string) =>
	`${count.format(n)} ${n === 1 ? one : many}`;

export function describeMarketingWarmup(progress: MarketingWarmupProgress): WarmupCard | null {
	if (progress.status === 'no_domain') return null;

	if (progress.status === 'graduated') {
		return {
			graduated: true,
			headline: 'Fully warmed up',
			stepLabel: `All ${progress.total_steps} steps complete`,
			step: progress.total_steps,
			totalSteps: progress.total_steps,
			today: null,
			unlockTitle: null,
			requirements: [],
			note: 'Your sending domain has earned its full sending rate. Your plan allowance still applies.'
		};
	}

	const limit = progress.daily_limit;
	const sent = Math.min(progress.sent_today, limit);
	const requirements: WarmupRequirement[] = [
		{
			key: 'days',
			met: progress.days_remaining === 0,
			label:
				progress.days_remaining === 0
					? 'Minimum time on this step reached'
					: `Wait ${plural(progress.days_remaining, 'more day', 'more days')}`
		},
		{
			key: 'sends',
			met: progress.sends_needed === 0,
			label:
				progress.sends_needed === 0
					? `Sent ${count.format(progress.sends_in_step)} emails on this step`
					: `Send ${plural(progress.sends_needed, 'more email', 'more emails')} to real customers`
		},
		{
			key: 'quality',
			met: progress.quality_ok,
			label: progress.quality_ok
				? 'Bounces and spam reports are low'
				: 'Too many bounces or spam reports on this step. Send only to customers who asked to hear from you.'
		}
	];

	return {
		graduated: false,
		headline: `${plural(limit, 'email', 'emails')} a day`,
		stepLabel: `Step ${progress.step} of ${progress.total_steps}`,
		step: progress.step,
		totalSteps: progress.total_steps,
		today: {
			sent,
			limit,
			fraction: limit > 0 ? sent / limit : 1,
			label: `${count.format(sent)} of ${count.format(limit)} sent today`
		},
		unlockTitle:
			progress.next_daily_limit === null
				? 'To finish warming up'
				: `To unlock ${count.format(progress.next_daily_limit)} a day`,
		requirements,
		note: progress.limit_overridden
			? 'UCRM support has set a fixed daily limit for your account.'
			: 'Anything over today’s limit waits and sends automatically tomorrow.'
	};
}
