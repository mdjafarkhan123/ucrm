export const OPERATION_TYPES = [
	'setup_email_delivery',
	'outbox_email_delivery',
	'onboarding_application_provisioning'
] as const;
export type OperationType = (typeof OPERATION_TYPES)[number];

export type TargetKind = 'onboarding_application' | 'organization' | 'platform';

export type NotificationTargetKind = TargetKind | 'operation_attempt';
