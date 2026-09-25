import type { SesEvent } from '$lib/server/marketing/ses-events';

// Maps an SES delivery event onto the lowercase vocabulary process_communication_provider_callbacks already
// understands (event_kind on communication_provider_callback_events). This SQL function is provider-neutral --
// it reads any channel='email' row regardless of provider -- so only this mapping, never the SQL, is new.
export function operationalCallbackEventKind(event: SesEvent): string {
	switch (event.eventType) {
		case 'Delivery':
			return 'delivered';
		case 'Bounce':
			return event.bounce?.bounceType === 'Permanent' ? 'hard_bounce' : 'soft_bounce';
		case 'Complaint':
			return 'complaint';
		case 'DeliveryDelay':
			return 'deferred';
		default:
			return 'other';
	}
}
