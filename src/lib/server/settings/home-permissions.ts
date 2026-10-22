import { hasPermission } from '$lib/server/access/permission';
import type { EffectiveOrganizationAccess } from '$lib/server/access/effective';

// Which Settings destinations this member may open. The Settings home and its figures both ask, so a
// member is never shown (or counted) something they cannot open.
export function settingsHomePermissions(access: EffectiveOrganizationAccess) {
	return {
		business_edit: hasPermission(access, 'settings.business.edit'),
		team_manage: hasPermission(access, 'team.manage'),
		communications_manage: hasPermission(access, 'conversations.manage_connections'),
		// Snippets are gated on the same permission as sending a message, not channel management --
		// a granted staff member who can send but not manage connections still needs this card.
		// Snippets and reply templates only exist to be dropped into an inbox reply, so they go
		// with the shared inbox when the plan does not include it.
		snippets_manage:
			access.features['communications.inbox'] === true &&
			hasPermission(access, 'conversations.send'),
		taxes_manage: hasPermission(access, 'settings.taxes.manage'),
		price_book_manage: hasPermission(access, 'settings.price_book.manage'),
		checklists_manage: hasPermission(access, 'settings.checklists.manage'),
		forms_manage: hasPermission(access, 'settings.forms.manage'),
		reviews_manage: hasPermission(access, 'reviews.manage'),
		quotes_manage: hasPermission(access, 'settings.quotes.manage'),
		invoices_manage: hasPermission(access, 'settings.invoices.manage'),
		payments_manage: hasPermission(access, 'settings.payments.manage'),
		// The Pipeline card goes with the Pipeline: no board, no settings for it.
		pipeline_view: hasPermission(access, 'pipeline.view'),
		// Whether Automation would show for this member — plan includes it and they may view it. In 6B
		// the card is still held back by a journey-ready flag on the client, so this alone never
		// reveals it; it wires the gate so publishing the feature in 6D turns the card on.
		automations_view: hasPermission(access, 'automations.view')
	};
}
