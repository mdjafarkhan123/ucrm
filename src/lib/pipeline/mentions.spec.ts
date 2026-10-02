import { describe, expect, it } from 'vitest';
import {
	insertMention,
	matchTeammates,
	mentionQueryAt,
	mentionsStillIn,
	splitMentions
} from './mentions';

describe('mentionQueryAt', () => {
	it('finds what is typed after an @ at the start or after a space', () => {
		expect(mentionQueryAt('@sa', 3)).toEqual({ start: 0, query: 'sa' });
		expect(mentionQueryAt('Ask @jo', 7)).toEqual({ start: 4, query: 'jo' });
		expect(mentionQueryAt('Ask @', 5)).toEqual({ start: 4, query: '' });
	});

	it('ignores an email address and a finished word', () => {
		expect(mentionQueryAt('mail sam@site.com', 17)).toBeNull();
		expect(mentionQueryAt('Ask @jo then', 12)).toBeNull();
	});
});

describe('insertMention', () => {
	it('replaces the typed part with the full name and puts the caret after it', () => {
		const at = mentionQueryAt('Ask @sa about it', 7)!;
		expect(insertMention('Ask @sa about it', at, 'Sam Lee')).toEqual({
			text: 'Ask @Sam Lee about it',
			caret: 13
		});
	});
});

describe('matchTeammates', () => {
	const team = [
		{ id: '1', full_name: 'Sam Lee' },
		{ id: '2', full_name: 'Alex Samson' },
		{ id: '3', full_name: null }
	];

	it('matches the start of any word, ignoring case', () => {
		expect(matchTeammates(team, 'sam').map((member) => member.id)).toEqual(['1', '2']);
		expect(matchTeammates(team, 'LEE').map((member) => member.id)).toEqual(['1']);
	});

	it('lists everyone with a name when nothing is typed yet', () => {
		expect(matchTeammates(team, '').map((member) => member.id)).toEqual(['1', '2']);
	});
});

describe('mentionsStillIn', () => {
	it('keeps only people whose @Name is still in the text, once each', () => {
		const picked = [
			{ id: '1', name: 'Sam Lee' },
			{ id: '1', name: 'Sam Lee' },
			{ id: '2', name: 'Alex' }
		];
		expect(mentionsStillIn('Thanks @Sam Lee', picked)).toEqual(['1']);
	});
});

describe('splitMentions', () => {
	it('marks the longest matching name', () => {
		expect(splitMentions('Hi @Sam Lee!', ['Sam', 'Sam Lee'])).toEqual([
			{ text: 'Hi ', mention: false },
			{ text: '@Sam Lee', mention: true },
			{ text: '!', mention: false }
		]);
	});

	it('leaves text alone when nobody is mentioned', () => {
		expect(splitMentions('a+b (c)', [])).toEqual([{ text: 'a+b (c)', mention: false }]);
	});
});
