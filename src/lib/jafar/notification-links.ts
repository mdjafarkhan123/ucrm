/**
 * Where a notification points. Shared by the server (alert emails need an absolute link) and
 * the browser (the bell and history list need the same destination), so a notification can
 * never lead one place in an email and somewhere else in the panel.
 */
export type NotificationTarget = {
	target_kind: 'onboarding_application' | 'organization' | 'operation_attempt' | 'platform';
	target_id: string | null;
};

export function notificationLinkPath(target: NotificationTarget) {
	if (!target.target_id) return '/jafar';
	switch (target.target_kind) {
		case 'onboarding_application':
			return `/jafar/prospects?application=${target.target_id}`;
		case 'organization':
			return `/jafar/organizations/${target.target_id}`;
		case 'operation_attempt':
			return `/jafar/operations?operation=${target.target_id}`;
		default:
			return '/jafar';
	}
}
