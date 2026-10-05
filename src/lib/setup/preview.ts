// Client onboarding E3: the preview and the one correction round (plan §6). Jafar writes the preview as cards and
// releases it; the client picks a choice on each card and sends their notes once. Industry reference: Filestage
// and Ziflow proofing (versions, a decision per item, one Submit), Rocketlane and GuideCX deliverable review, and
// agencies' "one revision round included".
//
// Jafar's choices of 2026-10-05: on a preview that opens the correction round a card is Looks right or Needs a
// change; once the round is used, Looks right, Uplift made a mistake (always fixed free), or something new, which
// arrives already sorted as New request. Jafar sorts every sent note, and the client sees his label. Mirrors
// supabase/migrations/20261101090000_setup_previews.sql.

export const PREVIEW_CHOICES = [
	'looks_right',
	'needs_change',
	'uplift_mistake',
	'new_request'
] as const;
export type PreviewChoice = (typeof PREVIEW_CHOICES)[number];

export const PREVIEW_KINDS = ['correction', 'uplift_error', 'new_request'] as const;
export type PreviewKind = (typeof PREVIEW_KINDS)[number];

export const PREVIEW_CARDS_MAX = 15;
export const PREVIEW_TITLE_MAX = 80;
export const PREVIEW_SUMMARY_MAX = 2000;
export const PREVIEW_LINK_MAX = 500;
export const PREVIEW_NOTE_MAX = 2000;
export const PREVIEW_SCREENSHOTS_MAX = 5;
export const PREVIEW_SCREENSHOT_BYTES_MAX = 10 * 1024 * 1024;
export const PREVIEW_SCREENSHOTS_TOTAL_BYTES = 20 * 1024 * 1024;
export const PREVIEW_SCREENSHOT_TYPES = [
	'image/jpeg',
	'image/png',
	'image/webp',
	'image/gif'
] as const;

/** A photo uploaded straight to storage, as Chat with Uplift's files are. */
export type PreviewScreenshot = {
	object_key: string;
	file_name: string;
	mime_type: string;
	byte_size: number;
	has_thumbnail: boolean;
};

/** A screenshot as a save sends it: the stored photo, or a fresh upload the route will measure. */
export type PreviewScreenshotUpload = Omit<PreviewScreenshot, 'byte_size'> & { byte_size?: number };

/** Where one side's screenshots upload to (POST) and are shown from. */
export type PreviewScreenshotUrls = {
	presign: string;
	view: (objectKey: string, size: 'thumb' | 'full') => string;
};

export type PreviewCard<Shot = PreviewScreenshot> = {
	id: string;
	title: string;
	summary: string;
	link: string | null;
	screenshots: Shot[];
};

export type PreviewNote<Shot = PreviewScreenshot> = {
	card_id: string;
	choice: PreviewChoice;
	note: string | null;
	screenshots: Shot[];
	updated_at: string;
	/** Jafar's label, once sent; a "something new" note arrives already labelled New request. */
	kind: PreviewKind | null;
};

export type PreviewVersion<Shot = PreviewScreenshot> = {
	version: number;
	released_at: string;
	/** True while the client has not yet used their one correction round. */
	correction_round: boolean;
	notes_sent_at: string | null;
	notes_sent_by_name: string | null;
	cards: PreviewCard<Shot>[];
	notes: PreviewNote<Shot>[];
};

/** The choices a card offers on a version. */
export function previewChoices(correctionRound: boolean): PreviewChoice[] {
	return correctionRound
		? ['looks_right', 'needs_change']
		: ['looks_right', 'uplift_mistake', 'new_request'];
}

/** The choices as buttons, in the client's words. */
export const PREVIEW_CHOICE_LABEL: Record<PreviewChoice, string> = {
	looks_right: 'Looks right',
	needs_change: 'Needs a change',
	uplift_mistake: 'Uplift made a mistake',
	new_request: 'Something new'
};

/** What the note box asks, by choice. */
export const PREVIEW_NOTE_PROMPT: Record<Exclude<PreviewChoice, 'looks_right'>, string> = {
	needs_change: 'What should change?',
	uplift_mistake: 'What is wrong?',
	new_request: 'What would you like?'
};

/** Jafar's labels, as the client reads them beside their note. */
export const PREVIEW_KIND_LABEL: Record<PreviewKind, string> = {
	correction: 'Correction',
	uplift_error: 'Our mistake (free)',
	new_request: 'New request — we’ll talk about this separately'
};

/** The same labels, short, for Jafar's buttons. */
export const PREVIEW_KIND_OWNER_LABEL: Record<PreviewKind, string> = {
	correction: 'Correction',
	uplift_error: 'Our mistake',
	new_request: 'New request'
};

/** Notes that ask for something — every one Jafar has to sort. */
export const askingNotes = <Shot>(notes: PreviewNote<Shot>[]) =>
	notes.filter((note) => note.choice !== 'looks_right');

/** Whether the client can send: at least one card asks for something, and nothing is sent yet. */
export function canSendPreviewNotes(preview: PreviewVersion<unknown>): boolean {
	return preview.notes_sent_at === null && askingNotes(preview.notes).length > 0;
}

/** Cards the client has not picked a choice on yet. */
export function unansweredCards<Shot>(preview: PreviewVersion<Shot>): PreviewCard<Shot>[] {
	const answered = new Set(preview.notes.map((note) => note.card_id));
	return preview.cards.filter((card) => !answered.has(card.id));
}

/** The cards a fresh draft starts with: one per part of the package (plan §6), each for Jafar to write. */
const STARTER_CARDS: { service: string | null; title: string }[] = [
	{ service: null, title: 'Your business details' },
	{ service: null, title: 'Services and service area' },
	{ service: 'website', title: 'Website' },
	{ service: 'website', title: 'Forms and where new leads go' },
	{ service: 'calls_texting', title: 'Calls and texts' },
	{ service: 'google_profile', title: 'Google profile' },
	{ service: 'reviews', title: 'Reviews' },
	{ service: 'marketing', title: 'Marketing drafts' },
	{ service: null, title: 'CRM settings and imports' }
];

export function starterPreviewCards(serviceKeys: readonly string[]) {
	return STARTER_CARDS.filter((card) => !card.service || serviceKeys.includes(card.service)).map(
		(card) => card.title
	);
}

/** The project's preview, as the step tracker reads it: the newest released version. */
export type PreviewFacts = {
	version: number;
	released_at: string;
	notes_sent_at: string | null;
};
