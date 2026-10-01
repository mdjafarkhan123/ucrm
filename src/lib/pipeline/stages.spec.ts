import { describe, expect, it } from 'vitest';
import {
	canMoveColumn,
	moveColumn,
	placeCustomStages,
	sectionColumns,
	type CustomStage,
	type SectionColumn
} from './stages';
import { pipelineSettingsSchema } from '$lib/server/validation/settings.schema';

const stage = (
	id: string,
	section: CustomStage['section'],
	after_stage: CustomStage['after_stage']
): CustomStage => ({ id, section, name: id, after_stage });

const names = (columns: SectionColumn[]) =>
	columns.map((column) => (column.kind === 'protected' ? column.key : column.stage.name));

describe('sectionColumns', () => {
	const stages = [
		stage('follow up', 'request', 'new_request'),
		stage('site notes', 'request', 'assessment_scheduled'),
		stage('quote prep', 'request', 'assessment_completed'),
		stage('waiting', 'quote', 'quote_awaiting_response')
	];

	it('puts each custom stage straight after the protected stage it follows', () => {
		expect(names(sectionColumns('request', true, stages))).toEqual([
			'new_request',
			'follow up',
			'assessment_unscheduled',
			'assessment_scheduled',
			'site notes',
			'assessment_completed',
			'quote prep'
		]);
		expect(names(sectionColumns('quote', true, stages))).toEqual([
			'quote_draft',
			'quote_awaiting_response',
			'waiting',
			'quote_changes_requested'
		]);
	});

	it('gathers stages saved inside Assessment after the one collapsed column', () => {
		expect(names(sectionColumns('request', false, stages))).toEqual([
			'new_request',
			'follow up',
			'assessment',
			'site notes',
			'quote prep'
		]);
	});

	it('never lets a stage cross into the other section', () => {
		expect(names(sectionColumns('quote', false, stages))).not.toContain('follow up');
	});
});

describe('moving a custom stage', () => {
	const columns = sectionColumns('quote', false, [
		stage('waiting', 'quote', 'quote_changes_requested')
	]);

	it('moves it between protected stages and re-reads the stage it follows', () => {
		const moved = moveColumn(columns, 3, -1);
		expect(names(moved)).toEqual([
			'quote_draft',
			'quote_awaiting_response',
			'waiting',
			'quote_changes_requested'
		]);
		expect(placeCustomStages(moved)[0].after_stage).toBe('quote_awaiting_response');
	});

	it('keeps the first stage of a section first, and leaves protected stages alone', () => {
		const second = moveColumn(moveColumn(columns, 3, -1), 2, -1);
		expect(names(second)[0]).toBe('quote_draft');
		expect(canMoveColumn(second, 1, -1)).toBe(false);
		expect(canMoveColumn(second, 0, 1)).toBe(false);
		expect(canMoveColumn(columns, 3, 1)).toBe(false);
	});

	it('places a stage after the collapsed Assessment column behind its last stage', () => {
		const collapsed = sectionColumns('request', false, [
			stage('follow up', 'request', 'new_request')
		]);
		const moved = moveColumn(collapsed, 1, 1);
		expect(placeCustomStages(moved)[0].after_stage).toBe('assessment_completed');
	});
});

describe('pipelineSettingsSchema', () => {
	const settings = (stages: unknown[]) => ({
		expected_revision: 1,
		detailed_assessment_stages: false,
		stages
	});
	const fresh = (name: string, section = 'quote', after_stage = 'quote_draft') => ({
		id: null,
		section,
		name,
		after_stage
	});

	it('accepts the same name once in each section', () => {
		const parsed = pipelineSettingsSchema.safeParse(
			settings([fresh('On hold'), fresh('On hold', 'request', 'new_request')])
		);
		expect(parsed.success).toBe(true);
	});

	it('refuses a repeated name in one section, whatever the capitals', () => {
		const parsed = pipelineSettingsSchema.safeParse(
			settings([fresh('Waiting on customer'), fresh(' waiting on CUSTOMER ')])
		);
		expect(parsed.success).toBe(false);
		expect(parsed.error?.issues[0].path).toEqual(['stages', 1, 'name']);
	});

	it('refuses the name of a built-in stage in the same section', () => {
		expect(pipelineSettingsSchema.safeParse(settings([fresh('Draft')])).success).toBe(false);
		expect(
			pipelineSettingsSchema.safeParse(settings([fresh('Draft', 'request', 'new_request')])).success
		).toBe(true);
	});

	it('refuses a 26th stage', () => {
		const stages = Array.from({ length: 26 }, (_, index) => fresh(`Stage ${index + 1}`));
		const parsed = pipelineSettingsSchema.safeParse(settings(stages));
		expect(parsed.success).toBe(false);
		expect(parsed.error?.issues[0].message).toBe('A pipeline can have up to 25 custom stages.');
	});

	it('refuses a stage placed after a stage of the other section', () => {
		expect(
			pipelineSettingsSchema.safeParse(settings([fresh('Waiting', 'quote', 'new_request')])).success
		).toBe(false);
	});
});
