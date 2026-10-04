import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import { readSetupState } from '$lib/server/setup/read';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';
import { unusableSetupFile } from '$lib/server/setup/files';
import { unusableProtectedDocument } from '$lib/server/setup/protected-documents';
import { setupAnswersSchema, type SetupAnswersInput } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { catalogueFacts, type SetupAnswers, type SetupFact } from '$lib/setup/catalogue';
import { setupListFileIds, type SetupListRow } from '$lib/setup/lists';
import { keptSetupPickIds, setupPickIds } from '$lib/setup/picks';
import { setupReuseSource } from '$lib/setup/reuse';

// Autosave. Each answer is a draft the administrator can keep changing; nothing saved here is treated as
// a final, attested answer (ADR 0005).
export const PATCH: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	// Checked against the version published now, as this client sees it, so a question Jafar just removed or
	// one from a stage outside their package is refused.
	const catalogue = await readOrganizationSetupCatalogue(event.locals.supabase, organizationId);
	if (!catalogue) return databaseError();

	const facts = catalogueFacts(catalogue);

	// A5f: a pick is checked against its list as saved, and a list's save tidies the picks made from it, so
	// both need the organization's saved answers. A5g: so do a reuse's "Yes, use this" and a save of the
	// answer it means. Other saves skip the read.
	const picks = [...facts.values()].filter((fact) => fact.kind === 'pick');
	const reuses = [...facts.values()].filter((fact) => fact.reuseFrom);
	const sentKeys = new Set(
		(Array.isArray((body as { answers?: unknown })?.answers)
			? ((body as { answers: unknown[] }).answers as { fact_key?: unknown }[])
			: []
		).map((answer) => answer?.fact_key)
	);
	let saved: SetupAnswers = {};
	if (
		picks.some((pick) => sentKeys.has(pick.key) || sentKeys.has(pick.pickFrom)) ||
		reuses.some((reuse) => sentKeys.has(reuse.key) || sentKeys.has(reuse.reuseFrom))
	) {
		const state = await readSetupState(event.locals.supabase, organizationId);
		if (!state) return databaseError();
		saved = state.answers;
	}

	const parsed = setupAnswersSchema(facts, saved).safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	// One save holds at most 50 answers; a pick left untidied only names a row nobody reads any more, and a
	// "Yes, use this" left behind counts as unanswered (setupAnswerGiven).
	const answers = [
		...parsed.data.answers,
		...[
			...prunedPicks(picks, parsed.data.answers, saved),
			...clearedReuses(reuses, parsed.data.answers, saved)
		].slice(0, 50 - parsed.data.answers.length)
	];

	// A photo or file answer may only hold this organization's own setup uploads that are still usable.
	// A5e: the same goes for the file boxes in a list's rows; B9a: and for a protected file answer.
	for (const answer of answers) {
		const fact = facts.get(answer.fact_key);
		if (!Array.isArray(answer.value)) continue;
		const ids =
			fact?.kind === 'file'
				? (answer.value as string[])
				: fact?.kind === 'list'
					? setupListFileIds(answer.value as SetupListRow[], fact.listFields ?? [])
					: [];
		const protectedIds = fact?.kind === 'protected_file' ? (answer.value as string[]) : [];
		if (ids.length === 0 && protectedIds.length === 0) continue;
		let unusable: string | null;
		try {
			// B9a: a protected file answer holds only this question's own protected documents.
			unusable = protectedIds.length
				? await unusableProtectedDocument(organizationId, answer.fact_key, protectedIds)
				: await unusableSetupFile(organizationId, ids);
		} catch (error) {
			console.error('Could not check setup answer files.', error);
			return databaseError();
		}
		if (unusable)
			return validationError({
				[answer.fact_key]: 'One of these files could not be kept. Remove it and try again.'
			});
	}

	const { data, error } = await event.locals.supabase.rpc('save_organization_setup_answers', {
		target_organization_id: organizationId,
		new_answers: answers
	});
	if (error) return setupWriteError(error);

	return json(data, { headers: NO_STORE_HEADERS });
};

type AnswerWrite = SetupAnswersInput['answers'][number];

/**
 * A5f: when a save changes a list, every saved pick of it loses the rows the list no longer holds, so a pick
 * never names a row that is gone. A pick left with none is cleared. A pick sent in the same save was already
 * checked against the new list.
 */
function prunedPicks(
	picks: SetupFact[],
	writes: AnswerWrite[],
	saved: SetupAnswers
): AnswerWrite[] {
	const sent = new Map(writes.map((write) => [write.fact_key, write]));
	return picks.flatMap((pick): AnswerWrite[] => {
		const list = sent.get(pick.pickFrom ?? '');
		if (!list || sent.has(pick.key) || saved[pick.key]?.availability !== 'have') return [];
		const ids = setupPickIds(saved[pick.key]?.value);
		const rows = list.availability === 'have' ? (list.value as SetupListRow[]) : [];
		const kept = keptSetupPickIds(ids, rows);
		if (kept.length === ids.length) return [];
		return [
			{
				fact_key: pick.key,
				availability: kept.length ? 'have' : null,
				value: kept.length ? kept : null,
				note: null
			}
		];
	});
}

/**
 * A5g: when a save leaves an earlier answer not given — cleared, "not yet" or "need help" — every saved
 * "Yes, use this" of it is cleared too, so the client is asked again rather than shown a confirmation of
 * nothing. A reuse sent in the same save was already checked against the new answer.
 */
function clearedReuses(
	reuses: SetupFact[],
	writes: AnswerWrite[],
	saved: SetupAnswers
): AnswerWrite[] {
	const sent = new Map(writes.map((write) => [write.fact_key, write]));
	return reuses.flatMap((reuse): AnswerWrite[] => {
		const source = sent.get(reuse.reuseFrom ?? '');
		const answer = saved[reuse.key];
		if (!source || source.availability === 'have' || sent.has(reuse.key)) return [];
		if (answer?.availability !== 'have' || setupReuseSource(answer.value) === null) return [];
		return [{ fact_key: reuse.key, availability: null, value: null, note: null }];
	});
}
