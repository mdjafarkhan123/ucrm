import { describe, expect, it } from 'vitest';
import {
	jafarMessageTemplateKey,
	jafarOperationTargetKey,
	jafarOrganizationEmailDomainRemovalKey,
	jafarOrganizationKey,
	jafarOrganizationSmsAdjustmentsKey,
	jafarOrganizationsListKey,
	jafarProspectKey,
	jafarProspectsListKey,
	jafarSettingsCleanupImpactKey
} from './query-keys';

describe('jafar query-key factories', () => {
	it('produces the same key for the same arguments', () => {
		expect(jafarOrganizationKey('org-1')).toEqual(jafarOrganizationKey('org-1'));
		expect(jafarOrganizationSmsAdjustmentsKey('org-1')).toEqual(
			jafarOrganizationSmsAdjustmentsKey('org-1')
		);
		expect(jafarProspectsListKey('new', 'acme')).toEqual(jafarProspectsListKey('new', 'acme'));
	});

	it('changes the key when the organization differs, so one organization can never read another’s cache', () => {
		expect(jafarOrganizationKey('org-1')).not.toEqual(jafarOrganizationKey('org-2'));
		expect(jafarOrganizationSmsAdjustmentsKey('org-1')).not.toEqual(
			jafarOrganizationSmsAdjustmentsKey('org-2')
		);
	});

	it('nests a sub-resource key under its organization key', () => {
		const base = jafarOrganizationKey('org-1');
		const sub = jafarOrganizationSmsAdjustmentsKey('org-1');
		expect(sub.slice(0, base.length)).toEqual(base);
	});

	it('changes the key when a filter changes', () => {
		expect(jafarOrganizationsListKey('acme', '')).not.toEqual(
			jafarOrganizationsListKey('other', '')
		);
		expect(jafarOrganizationsListKey('acme', '')).not.toEqual(
			jafarOrganizationsListKey('acme', 'access_overdue')
		);
		expect(jafarProspectsListKey('new', '')).not.toEqual(jafarProspectsListKey('awaiting', ''));
		expect(jafarOperationTargetKey('org-1')).not.toEqual(jafarOperationTargetKey('org-2'));
	});

	it('accepts a null selection without throwing, for a detail view with nothing chosen yet', () => {
		expect(jafarProspectKey(null)).toEqual(['jafar', 'prospect', null]);
		expect(jafarMessageTemplateKey(null)).toEqual(['jafar', 'message-templates', null]);
		expect(jafarOperationTargetKey(null)).toEqual(['jafar', 'operations', 'target', null]);
	});

	it('keeps an optional trailing id distinct from the same key with no id', () => {
		expect(jafarOrganizationEmailDomainRemovalKey('org-1', 'sending-1')).not.toEqual(
			jafarOrganizationEmailDomainRemovalKey('org-1', undefined)
		);
	});

	it('gives the cleanup-impact preview its own key per organization', () => {
		expect(jafarSettingsCleanupImpactKey('org-1')).not.toEqual(
			jafarSettingsCleanupImpactKey('org-2')
		);
		expect(jafarSettingsCleanupImpactKey('none')).toEqual([
			'jafar',
			'settings',
			'cleanup',
			'impact',
			'none'
		]);
	});
});
