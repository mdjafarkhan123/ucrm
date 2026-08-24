import { permissionIsEnabled, type EffectiveOrganizationAccess } from './effective';
import type { ContractorRole } from './contractor';

export const teamAccessRoles = ['admin', 'office', 'sales', 'field', 'finance'] as const;
export type TeamAccessRole = (typeof teamAccessRoles)[number];

type CapabilityDefinition = {
	id: string;
	name: string;
	description: string;
	controls: Array<{ id: string; permissionKey: string; label: string; example: string }>;
};

// This is the intentional translation boundary between CRM language and database permission keys. The
// browser receives the ids, labels, and examples below; it never receives a permissionKey.
const capabilityDefinitions: CapabilityDefinition[] = [
	{
		id: 'customers',
		name: 'Customers',
		description: 'Find and keep customer records accurate.',
		controls: [
			{
				id: 'view-customers',
				permissionKey: 'customers.view',
				label: 'View customers',
				example: 'Open customer and property details.'
			},
			{
				id: 'create-customers',
				permissionKey: 'customers.create',
				label: 'Add customers',
				example: 'Create a customer from new work.'
			},
			{
				id: 'edit-customers',
				permissionKey: 'customers.edit',
				label: 'Edit customer details',
				example: 'Update contacts and communication preferences.'
			},
			{
				id: 'manage-properties',
				permissionKey: 'property.manage',
				label: 'Manage properties',
				example: 'Add, edit, or archive a property.'
			},
			{
				id: 'archive-customers',
				permissionKey: 'customers.archive',
				label: 'Archive customers',
				example: 'Archive or restore a customer.'
			},
			{
				id: 'delete-customers',
				permissionKey: 'customers.delete',
				label: 'Delete customers',
				example: 'Move a customer to Recently Deleted.'
			},
			{
				id: 'merge-customers',
				permissionKey: 'customers.merge',
				label: 'Merge customers',
				example: 'Combine duplicate customer records.'
			},
			{
				id: 'import-export-customers',
				permissionKey: 'customers.import_export',
				label: 'Import and export customers',
				example: 'Work with customer lists in bulk.'
			},
			{
				id: 'view-customer-financials',
				permissionKey: 'customers.view_financials',
				label: 'View customer financials',
				example: 'See customer balances and lifetime revenue.'
			}
		]
	},
	{
		id: 'pipeline',
		name: 'Sales pipeline',
		description: 'Follow commercial work from enquiry to decision.',
		controls: [
			{
				id: 'view-pipeline',
				permissionKey: 'pipeline.view',
				label: 'View the pipeline',
				example: 'See open sales opportunities.'
			},
			{
				id: 'edit-pipeline',
				permissionKey: 'pipeline.edit',
				label: 'Manage pipeline work',
				example: 'Update an opportunity and its follow-up.'
			},
			{
				id: 'view-pipeline-values',
				permissionKey: 'pipeline.view_value',
				label: 'View pipeline values',
				example: 'See estimated values and column totals.'
			}
		]
	},
	{
		id: 'quotes',
		name: 'Quotes and Price Book',
		description: 'Prepare, send, and maintain quoted work.',
		controls: [
			{
				id: 'view-quotes',
				permissionKey: 'quotes.view',
				label: 'View quotes',
				example: 'Open quote details and their contents.'
			},
			{
				id: 'view-quote-prices',
				permissionKey: 'quotes.view_price',
				label: 'View quote prices',
				example: 'See quote prices and totals.'
			},
			{
				id: 'view-quote-costs',
				permissionKey: 'quotes.view_cost',
				label: 'View quote costs and profit',
				example: 'See internal cost and profit.'
			},
			{
				id: 'create-quotes',
				permissionKey: 'quotes.create',
				label: 'Create quotes',
				example: 'Start a quote, including from a request.'
			},
			{
				id: 'edit-quotes',
				permissionKey: 'quotes.edit',
				label: 'Edit draft quotes',
				example: 'Change a quote before it is sent.'
			},
			{
				id: 'send-quotes',
				permissionKey: 'quotes.send',
				label: 'Send quotes',
				example: 'Publish a quote for a customer.'
			},
			{
				id: 'record-quote-decisions',
				permissionKey: 'quotes.record_decision',
				label: 'Record quote decisions',
				example: 'Record an approval or decline given outside the app.'
			},
			{
				id: 'record-quote-deposits',
				permissionKey: 'quotes.record_deposit',
				label: 'Record quote deposits',
				example: 'Record or reverse an offline deposit.'
			},
			{
				id: 'view-price-book',
				permissionKey: 'catalog.view',
				label: 'View the Price Book',
				example: 'See reusable products and services.'
			},
			{
				id: 'manage-price-book',
				permissionKey: 'catalog.edit',
				label: 'Manage the Price Book',
				example: 'Add, change, or archive price list items.'
			}
		]
	},
	{
		id: 'business-settings',
		name: 'Business settings',
		description: 'Control shared business identity and hours.',
		controls: [
			{
				id: 'view-business-settings',
				permissionKey: 'settings.business.view',
				label: 'View business settings',
				example: 'See business profile, branding, and hours.'
			},
			{
				id: 'edit-business-settings',
				permissionKey: 'settings.business.edit',
				label: 'Edit business settings',
				example: 'Change business profile, branding, and hours.'
			}
		]
	},
	{
		id: 'team',
		name: 'Team',
		description: 'Manage people and their access.',
		controls: [
			{
				id: 'manage-team',
				permissionKey: 'team.manage',
				label: 'Manage team access',
				example: 'Invite people and manage team roles.'
			}
		]
	}
];

const controls = capabilityDefinitions.flatMap((capability) => capability.controls);
const controlsById = new Map(controls.map((control) => [control.id, control]));
const permissionKeys = new Set(controls.map((control) => control.permissionKey));

export function isTeamAccessControlId(value: string): value is string {
	return controlsById.has(value);
}

export function permissionKeyForTeamAccessControl(id: string) {
	return controlsById.get(id)?.permissionKey;
}

export function isTeamAccessPermissionKey(value: string) {
	return permissionKeys.has(value);
}

export function teamAccessEditorModel(input: {
	actorRole: ContractorRole;
	actorUserId: string;
	targetUserId: string;
	targetRole: ContractorRole;
	targetStatus: string;
	accessRevision: number;
	rolePermissionKeys: Map<string, Set<string>>;
	overrides: Map<string, 'grant' | 'deny'>;
	features: EffectiveOrganizationAccess['features'];
}) {
	const canEditTarget =
		input.actorUserId !== input.targetUserId &&
		input.targetRole !== 'owner' &&
		(input.actorRole === 'owner' || input.targetRole !== 'admin');
	const reason = canEditTarget
		? null
		: input.actorUserId === input.targetUserId
			? 'People cannot change their own role or access.'
			: input.targetRole === 'owner'
				? 'The Owner’s access can only change through ownership transfer.'
				: 'Only the Owner can change an Administrator’s access.';

	return {
		member: {
			role: input.targetRole,
			status: input.targetStatus,
			access_revision: input.accessRevision,
			can_edit: canEditTarget,
			cannot_edit_reason: reason,
			is_adjusted: input.overrides.size > 0
		},
		roles: teamAccessRoles.map((role) => ({
			id: role,
			label: role === 'admin' ? 'Administrator' : `${role[0].toUpperCase()}${role.slice(1)}`,
			summary: roleSummary(role),
			available: input.actorRole === 'owner' || role !== 'admin',
			default_control_ids: controls
				.filter((control) => input.rolePermissionKeys.get(role)?.has(control.permissionKey))
				.map((control) => control.id)
		})),
		capabilities: capabilityDefinitions.map((capability) => ({
			id: capability.id,
			name: capability.name,
			description: capability.description,
			controls: capability.controls.map((control) => {
				const adjustment = input.overrides.get(control.permissionKey) ?? null;
				const includedInRole =
					input.rolePermissionKeys.get(input.targetRole)?.has(control.permissionKey) ?? false;
				const available = permissionIsEnabled(control.permissionKey, input.features);
				return {
					id: control.id,
					label: control.label,
					example: control.example,
					included_in_role: includedInRole,
					effective: available && (adjustment ? adjustment === 'grant' : includedInRole),
					adjustment,
					available
				};
			})
		}))
	};
}

function roleSummary(role: TeamAccessRole) {
	return {
		admin: 'Runs the business and manages ordinary Team settings.',
		office: 'Coordinates customers, quotes, scheduling, and office work.',
		sales: 'Works with customers, requests, pipeline, and quotes.',
		field: 'Works on assigned field work without financial access.',
		finance: 'Works with quotes, invoices, payments, and financial reporting.'
	}[role];
}
