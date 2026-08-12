import { describe, expect, it } from 'vitest';
import { permissionIsEnabled } from './effective';
import { resolveMemberPermissionMap } from './contractor';

describe('contractor access composition', () => {
	it('uses employee overrides after role defaults', () => {
		expect(
			resolveMemberPermissionMap(
				['customer.view', 'customer.edit', 'pipeline.view'],
				[
					{ permission_key: 'customer.edit', override_state: 'deny' },
					{ permission_key: 'invoice.view', override_state: 'grant' }
				],
				{
					'core.customers_properties': true,
					'sales.pipeline': true,
					'core.invoices_payments': false
				}
			)
		).toEqual({
			'customer.view': true,
			'customer.edit': false,
			'pipeline.view': true,
			'invoice.view': false
		});
	});

	it('does not let an employee permission bypass a disabled package feature', () => {
		expect(permissionIsEnabled('pipeline.edit', { 'sales.pipeline': false })).toBe(false);
		expect(permissionIsEnabled('customer.view', { 'core.customers_properties': false })).toBe(
			false
		);
		expect(permissionIsEnabled('unknown.permission', {})).toBe(true);
	});
});
