// Client onboarding B13: Check and send to Uplift (plan §3.10, blueprint stage 12). The system writes this
// stage; Jafar never edits it. It reads back every task the client is asked, with what Uplift can continue
// without kept apart from what still stops the send, and the confirmations the final approver ticks. Follows
// GOV.UK "Check answers" and "Complete multiple tasks": send once every task is done (Jafar, 2026-10-04).
//
// After a send the client may still change answers. Each change is shown against the newest send, and "Send
// changes to Uplift" takes the next snapshot (Jafar, 2026-10-04). The snapshot itself never changes (ADR 0005).

import { setupAnswerLines } from '$lib/setup/answer-lines';
import {
	catalogueFacts,
	missingRequiredFacts,
	sectionFacts,
	sectionStatus,
	setupAnswerGiven,
	setupAnswerShortfall,
	shownCatalogueFacts,
	type SetupAnswer,
	type SetupAnswers,
	type SetupCatalogue,
	type SetupFact
} from '$lib/setup/catalogue';
import { setupFileIds } from '$lib/setup/files';
import { setupListRows } from '$lib/setup/lists';
import { keptSetupPickIds, setupPickIds, setupPickRowName } from '$lib/setup/picks';
import { setupReuseSource } from '$lib/setup/reuse';

/** The stage's page, `/setup/check-and-send`. A stage key never holds a hyphen, so no stage Jafar adds can take it. */
export const SETUP_CHECK_KEY = 'check-and-send';
export const SETUP_CHECK_TITLE = 'Check and send to Uplift';
export const SETUP_CHECK_DESCRIPTION =
	'Look over your answers, confirm a few things, and send your setup to Uplift.';

/** Bumped whenever a confirmation's wording changes; each send records it with the wording itself. */
export const SETUP_CONFIRMATIONS_VERSION = '2026-10-04';

export type SetupConfirmation = { key: string; wording: string };

/**
 * What the final approver confirms before sending, in the blueprint's order. A confirmation about a service
 * appears only when the package includes it; a client is never asked about something they did not buy.
 */
export function setupConfirmations(serviceKeys: ReadonlySet<string>): SetupConfirmation[] {
	const website = serviceKeys.has('website');
	const google = serviceKeys.has('google_profile');
	const owned = [website && 'domain', google && 'Google Business Profile']
		.filter(Boolean)
		.join(' and ');
	const list: (SetupConfirmation | false)[] = [
		{
			key: 'accurate',
			wording: 'The information in this setup is accurate to the best of my knowledge.'
		},
		{
			key: 'use_materials',
			wording:
				'Uplift may use the content, files, photos, testimonials and data I have supplied for the work in our package.'
		},
		{
			key: 'permission',
			wording:
				'I have permission to supply these materials, and I have told Uplift about any limits on how they may be used.'
		},
		{
			key: 'build_and_launch',
			wording: website
				? 'Uplift may prepare the services in our package. Nothing goes live, and no changes are made to our domain settings (DNS), until I approve the launch.'
				: 'Uplift may prepare the services in our package. Nothing goes live until I approve the launch.'
		},
		Boolean(owned) && {
			key: 'ownership',
			wording: `Our business stays the owner of our ${owned}. Uplift works only through access we grant and never needs our passwords.`
		},
		serviceKeys.has('calls_texting') && {
			key: 'phone_registration',
			wording:
				'Uplift may submit truthful details about our business to register our phone number and texting, and set up call routing the way I have described.'
		},
		{
			key: 'imports',
			wording:
				'Uplift imports our existing customers or other records only after I have seen a preview and approved it.'
		},
		serviceKeys.has('marketing') && {
			key: 'marketing_drafts',
			wording:
				'Marketing campaigns stay drafts. Nothing is sent until I approve who receives it and the message, separately.'
		}
	];
	return list.filter((item): item is SetupConfirmation => item !== false);
}

export type SetupCheckItemState = 'answered' | 'not_yet' | 'need_help' | 'skipped';

export type SetupCheckItem = {
	key: string;
	label: string;
	required: boolean;
	state: SetupCheckItemState;
	/** The answer in words; empty unless answered. */
	lines: string[];
	/** "Yes, use this": the earlier question's wording, whose answer `lines` shows. */
	same_as: string | null;
	/** What the client told Uplift beside "not yet" or "need help". */
	note: string | null;
	/** Different from the newest send. */
	changed: boolean;
};

/** Blueprint stage 12's labels, plus `unfinished`, which stops the send. */
export type SetupCheckStatus =
	'unfinished' | 'needs_help' | 'waiting' | 'optional_skipped' | 'complete';

/** Each status in words, with its badge colour. */
export const SETUP_CHECK_STATUS: Record<
	SetupCheckStatus,
	{ label: string; badge: 'success' | 'warning' | 'critical' | 'inactive' | 'informative' }
> = {
	unfinished: { label: 'Not finished', badge: 'critical' },
	needs_help: { label: 'Needs help', badge: 'warning' },
	waiting: { label: 'Waiting for item', badge: 'informative' },
	optional_skipped: { label: 'Optional items skipped', badge: 'inactive' },
	complete: { label: 'Complete', badge: 'success' }
};

export type SetupCheckSection = {
	key: string;
	title: string;
	status: SetupCheckStatus;
	/** Why an unfinished task stops the send, in words. */
	problem: string | null;
	items: SetupCheckItem[];
	/** Questions answered in the newest send that a changed answer has since hidden. */
	no_longer_asked: { key: string; label: string }[];
};

export type SetupCheck = {
	sections: SetupCheckSection[];
	/** Answers that differ from the newest send, counting those no longer asked. */
	changed_count: number;
	/** Every task is done; with a send already made, something has also changed. */
	can_send: boolean;
};

const sameAnswer = (a: SetupAnswer | undefined, b: SetupAnswer | undefined) =>
	(a?.availability ?? null) === (b?.availability ?? null) &&
	(a?.value ?? null) === (b?.value ?? null) &&
	(a?.note ?? null) === (b?.note ?? null);

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`;

/** An answer in words, for any kind of question. */
function answerLines(fact: SetupFact, value: string, answers: SetupAnswers): string[] {
	switch (fact.kind) {
		case 'file': {
			const count = setupFileIds(value).length;
			const photos = fact.fileKinds?.length === 1 && fact.fileKinds[0] === 'photo';
			return [`${plural(count, photos ? 'photo' : 'file', photos ? 'photos' : 'files')} added`];
		}
		case 'protected_file':
			return [`${plural(setupFileIds(value).length, 'document', 'documents')} received`];
		case 'pick': {
			// Named in the client's own order.
			const rows = setupListRows(answers[fact.pickFrom ?? '']?.value);
			const place = new Map(rows.map((row, index) => [row.id, index]));
			const names = keptSetupPickIds(setupPickIds(value), rows).map((id) => {
				const index = place.get(id) ?? 0;
				return setupPickRowName(rows[index], index, fact.pickNameKey);
			});
			return names.length ? [names.join(', ')] : [];
		}
		default:
			return setupAnswerLines(fact, value);
	}
}

/**
 * The check stage for one client: every task they are asked, read back. `sent` is the newest send's answers,
 * or null before the first.
 */
export function buildSetupCheck(
	catalogue: SetupCatalogue,
	answers: SetupAnswers,
	doneSections: ReadonlySet<string>,
	sent: SetupAnswers | null
): SetupCheck {
	const shown = shownCatalogueFacts(catalogue, answers);
	const facts = catalogueFacts(catalogue);
	let changedCount = 0;

	const sections = catalogue.sections.map((section): SetupCheckSection => {
		const asked = sectionFacts(section).filter((fact) => shown.has(fact.key));
		const items = asked.map((fact): SetupCheckItem => {
			const answer = answers[fact.key];
			const given = setupAnswerGiven(fact, answers);
			const changed = sent !== null && !sameAnswer(answer, sent[fact.key]);
			if (changed) changedCount += 1;
			if (!given || !answer)
				return {
					key: fact.key,
					label: fact.label,
					required: fact.required,
					state: 'skipped',
					lines: [],
					same_as: null,
					note: null,
					changed
				};
			if (answer.availability !== 'have')
				return {
					key: fact.key,
					label: fact.label,
					required: fact.required,
					state: answer.availability,
					lines: [],
					same_as: null,
					note: answer.note,
					changed
				};
			const source = setupReuseSource(answer.value);
			const sourceFact = source ? facts.get(source) : undefined;
			const sourceValue = source ? answers[source]?.value : null;
			return {
				key: fact.key,
				label: fact.label,
				required: fact.required,
				state: 'answered',
				lines:
					sourceFact && sourceValue
						? answerLines(sourceFact, sourceValue, answers)
						: answerLines(fact, answer.value ?? '', answers),
				same_as: sourceFact ? (fact.reuseLabel ?? sourceFact.label) : null,
				note: null,
				changed
			};
		});

		const noLongerAsked = sent
			? sectionFacts(section).filter((fact) => !shown.has(fact.key) && sent[fact.key])
			: [];
		changedCount += noLongerAsked.length;

		const missing = missingRequiredFacts(section, answers, shown).length;
		const shortfall = asked.some((fact) => setupAnswerShortfall(fact, answers) !== null);
		const done = sectionStatus(section, answers, doneSections.has(section.key), shown) === 'done';
		const problem =
			missing > 0
				? `${plural(missing, 'required question still needs', 'required questions still need')} an answer.`
				: shortfall
					? 'A question still needs more picked.'
					: !done
						? 'Not marked as done yet.'
						: null;

		return {
			key: section.key,
			title: section.title,
			status: problem
				? 'unfinished'
				: items.some((item) => item.state === 'need_help')
					? 'needs_help'
					: items.some((item) => item.state === 'not_yet')
						? 'waiting'
						: items.some((item) => item.state === 'skipped')
							? 'optional_skipped'
							: 'complete',
			problem,
			items,
			no_longer_asked: noLongerAsked.map((fact) => ({ key: fact.key, label: fact.label }))
		};
	});

	return {
		sections,
		changed_count: changedCount,
		can_send:
			sections.every((section) => section.status !== 'unfinished') &&
			(sent === null || changedCount > 0)
	};
}

/** The answers the snapshot keeps: every question asked now that has an answer of any kind. */
export function setupSnapshotFactKeys(catalogue: SetupCatalogue, answers: SetupAnswers): string[] {
	return [...shownCatalogueFacts(catalogue, answers)].filter((key) => answers[key]);
}
