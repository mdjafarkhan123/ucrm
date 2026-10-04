// Client onboarding C2: what Jafar's client page shows of a client's setup (plan §8) — every Send to Uplift,
// one of them read back by section, and the client's setup reminders. Built by
// `$lib/server/setup/client-page.ts`; the types live here so the page can read them.

import type { SetupCheckSection, SetupConfirmation } from '$lib/setup/check';
import type { SetupHelpItem } from '$lib/setup/help';
import type { SetupSectionReview } from '$lib/setup/review';

/** One file of a photo or file answer. Mirrors `SetupFileInfo` in `$lib/server/setup/files`. */
export type ClientSetupFile = {
	id: string;
	name: string;
	mime_type: string;
	size_bytes: number;
	state: 'checking' | 'ready' | 'refused' | 'removed';
	thumb_url: string | null;
	problem: string | null;
};

/** One Send to Uplift, without its answers. */
export type ClientSetupSend = {
	number: number;
	submitted_at: string;
	submitted_by_name: string;
	submitted_by_email: string;
};

export type ClientSetupSendView = ClientSetupSend & {
	/** The confirmations exactly as ticked, and the wording version they were shown in. */
	confirmations: SetupConfirmation[];
	confirmations_version: string;
	/** The answers by task, read against the setup version the client sent them in. */
	sections: SetupCheckSection[];
	/** The send this one's "Changed" marks compare with: the one before it, or null for the first. */
	compared_with: number | null;
	changed_count: number;
	/** The files of each photo or file answer, by question. */
	files: Record<string, ClientSetupFile[]>;
	/** Questions answered with protected documents, which open from the Protected documents list. */
	protected_questions: string[];
};

export type ClientSetupReminders = {
	paused_at: string | null;
	next_due_at: string | null;
	reminders_sent: number;
	last_sent_at: string | null;
};

export type ClientSetupView = {
	/** Newest first. */
	sends: ClientSetupSend[];
	/** The send asked for, or the newest; null before the first. */
	send: ClientSetupSendView | null;
	/** Uplift's review of each section of the newest send, by section (C3); null while an earlier send is shown. */
	reviews: Record<string, SetupSectionReview> | null;
	/** C3c: Uplift's to-do — the newest send's help requests, open first; null while an earlier send is shown. */
	help: SetupHelpItem[] | null;
	/** The country and currency the newest send gave, for Uplift's amount answers. */
	help_units: { country: string | null; currency: string | null };
	/** Answers the client has changed since the newest send and not sent yet. */
	unsent_changes: number;
	/** Null for a business that has no reminder timer (not provisioned as a paid client). */
	reminders: ClientSetupReminders | null;
};

/** The reminders' state in words, for the Setup tab. `sent`: setup is with Uplift, nothing sent back. */
export function clientSetupRemindersText(
	reminders: ClientSetupReminders,
	sent: boolean,
	formatDate: (iso: string) => string
): string {
	if (reminders.paused_at) return `Paused by Uplift on ${formatDate(reminders.paused_at)}.`;
	if (sent) return 'Off while Uplift reviews — the client has sent their setup.';
	if (reminders.next_due_at)
		return `On. The next one goes out around ${formatDate(reminders.next_due_at)} if the client stays quiet.`;
	return reminders.reminders_sent > 0
		? 'On. All three reminders for this quiet spell have gone out; any setup activity starts a new series.'
		: 'On. None is waiting right now.';
}
