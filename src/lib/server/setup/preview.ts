import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import type {
	PreviewCard,
	PreviewChoice,
	PreviewKind,
	PreviewNote,
	PreviewScreenshot,
	PreviewVersion
} from '$lib/setup/preview';

// Client onboarding E3: the preview and the one correction round (plan §6). Reads for both sides and the email
// that tells the client a preview is ready. A client keeps a handful of versions with at most 15 cards each, so
// every read here is two small queries keyed by the organization.

type Client = SupabaseClient<Database>;

const PREVIEW_COLUMNS =
	'version, cards, released_at, correction_round, notes_sent_at, notes_sent_by_name, updated_at';
const NOTE_COLUMNS = 'version, card_id, choice, note, screenshots, updated_at, sorted_kind';

type PreviewRow = {
	version: number;
	cards: unknown;
	released_at: string | null;
	correction_round: boolean | null;
	notes_sent_at: string | null;
	notes_sent_by_name: string | null;
	updated_at: string;
};

type NoteRow = {
	version: number;
	card_id: string;
	choice: string;
	note: string | null;
	screenshots: unknown;
	updated_at: string;
	sorted_kind: string | null;
};

const asScreenshots = (value: unknown) =>
	(Array.isArray(value) ? value : []) as PreviewScreenshot[];

function cardsFrom(value: unknown): PreviewCard[] {
	if (!Array.isArray(value)) return [];
	return value.map((card) => ({
		id: String(card.id),
		title: String(card.title),
		summary: String(card.summary),
		link: typeof card.link === 'string' ? card.link : null,
		screenshots: asScreenshots(card.screenshots)
	}));
}

function noteFrom(row: NoteRow): PreviewNote {
	return {
		card_id: row.card_id,
		choice: row.choice as PreviewChoice,
		note: row.note,
		screenshots: asScreenshots(row.screenshots),
		updated_at: row.updated_at,
		kind: row.sorted_kind as PreviewKind | null
	};
}

function versionFrom(row: PreviewRow, notes: NoteRow[]): PreviewVersion {
	return {
		version: row.version,
		released_at: row.released_at ?? row.updated_at,
		correction_round: row.correction_round ?? true,
		notes_sent_at: row.notes_sent_at,
		notes_sent_by_name: row.notes_sent_by_name,
		cards: cardsFrom(row.cards),
		notes: notes.filter((note) => note.version === row.version).map(noteFrom)
	};
}

/**
 * Every released version, newest first, with the client's notes. With the client's own session, row security
 * shows only released versions to its owners and administrators; with the service role, Jafar's draft is left out
 * here and read separately.
 */
export async function readReleasedPreviews(
	supabase: Client,
	organizationId: string
): Promise<PreviewVersion[]> {
	const [previews, notes] = await Promise.all([
		supabase
			.from('organization_setup_previews')
			.select(PREVIEW_COLUMNS)
			.eq('organization_id', organizationId)
			.not('released_at', 'is', null)
			.order('version', { ascending: false }),
		supabase
			.from('organization_setup_preview_notes')
			.select(NOTE_COLUMNS)
			.eq('organization_id', organizationId)
	]);
	if (previews.error) throw previews.error;
	if (notes.error) throw notes.error;
	return previews.data.map((row) => versionFrom(row, notes.data));
}

export type OwnerPreviewDraft = { version: number; cards: PreviewCard[]; updated_at: string };

/** Jafar's view: whether a preview can be written yet, his draft, and every released version. */
export async function readOwnerPreviews(supabase: Client, organizationId: string) {
	const [ready, draft, released] = await Promise.all([
		supabase
			.from('organization_setup_ready')
			.select('organization_id')
			.eq('organization_id', organizationId)
			.maybeSingle(),
		supabase
			.from('organization_setup_previews')
			.select('version, cards, updated_at')
			.eq('organization_id', organizationId)
			.is('released_at', null)
			.maybeSingle(),
		readReleasedPreviews(supabase, organizationId)
	]);
	if (ready.error) throw ready.error;
	if (draft.error) throw draft.error;
	return {
		ready: ready.data !== null,
		draft: draft.data
			? {
					version: draft.data.version,
					cards: cardsFrom(draft.data.cards),
					updated_at: draft.data.updated_at
				}
			: null,
		released
	};
}

type Recipient = { user_id: string; email: string; name: string | null };

const HTML_ESCAPE: Record<string, string> = {
	'&': '&amp;',
	'<': '&lt;',
	'>': '&gt;',
	'"': '&quot;',
	"'": '&#39;'
};

function escapeHtml(value: string) {
	return value.replace(/[&<>"']/g, (character) => HTML_ESCAPE[character] ?? character);
}

function greetingName(name: string | null) {
	const first = name?.trim().split(/\s+/)[0] ?? '';
	return first && !first.includes('@') ? first : 'there';
}

export function buildPreviewReadyEmail(input: {
	recipientName: string | null;
	organizationName: string;
	version: number;
	correctionRound: boolean;
	origin: string;
}) {
	const url = `${input.origin}/setup#preview`;
	const first = input.version === 1;
	const paragraphs = [
		first
			? `Hi ${greetingName(input.recipientName)}, Uplift has built ${input.organizationName}'s system and it is ready for you to review.`
			: `Hi ${greetingName(input.recipientName)}, Uplift has sent an updated preview of ${input.organizationName}'s system.`,
		input.correctionRound
			? `Look through each part and mark it Looks right or Needs a change. When you have been through them all, send your corrections together — your package includes one round of corrections.`
			: `Look through each part and mark it Looks right. If Uplift made a mistake, say so on that part and it will be fixed free.`
	];
	const after = `Nothing goes live until you approve it.`;

	const htmlContent = [
		...paragraphs.map((line) => `<p>${escapeHtml(line)}</p>`),
		`<p style="margin:20px 0"><a href="${escapeHtml(url)}" style="display:inline-block;padding:10px 20px;border-radius:6px;background:#111827;color:#ffffff;text-decoration:none;font-weight:600">Review your preview</a></p>`,
		`<p style="color:#6b7280;font-size:13px">${escapeHtml(after)}</p>`
	].join('\n');
	const textContent = [...paragraphs, `Review your preview: ${url}`, after].join('\n\n');

	return {
		subject: first ? 'Your system is ready to review' : 'Your updated preview is ready',
		htmlContent,
		textContent
	};
}

/**
 * Tells the client's owners and administrators a preview was released. Call it with the service role's client
 * after the release is recorded; the outbox key carries the version, so pressing Release again queues only what is
 * missing. Throws when nothing could be read or queued.
 */
export async function sendPreviewReadyEmails(
	client: Client,
	input: { organizationId: string; version: number; origin: string }
) {
	const [previewResult, organizationResult, recipientsResult] = await Promise.all([
		client
			.from('organization_setup_previews')
			.select('released_at, correction_round')
			.eq('organization_id', input.organizationId)
			.eq('version', input.version)
			.maybeSingle(),
		client.from('organizations').select('name').eq('id', input.organizationId).single(),
		client.rpc('owner_setup_review_recipients', { target_organization_id: input.organizationId })
	]);
	if (previewResult.error) throw previewResult.error;
	if (organizationResult.error) throw organizationResult.error;
	if (recipientsResult.error) throw recipientsResult.error;

	const preview = previewResult.data;
	if (!preview?.released_at) return 0;

	const recipients = (recipientsResult.data ?? []) as unknown as Recipient[];
	for (const recipient of recipients)
		await enqueueEmailDelivery(client, {
			templateKey: 'client_setup_preview_ready',
			target: { targetKind: 'organization', targetId: input.organizationId },
			idempotencyKey: `setup-preview:${input.organizationId}:${input.version}:${recipient.user_id}`,
			recipientEmail: recipient.email,
			...buildPreviewReadyEmail({
				recipientName: recipient.name,
				organizationName: organizationResult.data.name,
				version: input.version,
				correctionRound: preview.correction_round ?? true,
				origin: input.origin
			})
		});
	return recipients.length;
}
