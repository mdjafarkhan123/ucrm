import { describe, expect, it } from 'vitest';
import { handOffComposerDraft, takeComposerDraft } from './composer-draft';

const draft = { clientId: 'client-1', channel: 'sms' as const, subject: '', body: 'Here: link' };

describe('composer draft hand-off', () => {
	it('hands the draft over once, to its own conversation', () => {
		handOffComposerDraft(draft);
		expect(takeComposerDraft('client-1')).toEqual(draft);
		expect(takeComposerDraft('client-1')).toBeNull();
	});

	it('never gives one Client the draft written for another', () => {
		handOffComposerDraft(draft);
		expect(takeComposerDraft('client-2')).toBeNull();
		expect(takeComposerDraft('client-1')).toEqual(draft);
	});
});
