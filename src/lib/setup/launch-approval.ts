// Client onboarding E4: launch approval (plan §6). Once Uplift's checks are done, Jafar asks the final approver to
// approve the newest released preview; they approve on the Setup page when signed in with that email, or through a
// private emailed link. Industry reference: DocuSign's emailed signing link, Jobber's online quote approval,
// approvals in Rocketlane and GuideCX. Mirrors supabase/migrations/20261102090000_setup_launch_approvals.sql.

/** The sentence the approver agrees to. Mirrors private.setup_launch_approval_wording. */
export function launchApprovalWording(version: number) {
	return `I approve this website and system to go live, as shown in preview version ${version}.`;
}

export const LAUNCH_NOT_YET_NOTE_MAX = 2000;
export const LAUNCH_RECORD_REASON_MAX = 500;

export type LaunchApprovalMethod = 'signed_in' | 'link' | 'recorded';
export type LaunchApprovalClosedReason = 'new_release' | 'corrections_sent';

/** One request, as both the client and Jafar read it. The link itself is never read back. */
export type LaunchApprovalRequest = {
	id: string;
	version: number;
	requested_at: string;
	approver_name: string;
	approver_email: string;
	link_sent_at: string;
	link_expires_at: string;
	status: 'open' | 'approved' | 'cancelled';
	closed_reason: LaunchApprovalClosedReason | null;
	closed_at: string | null;
	not_yet_at: string | null;
	not_yet_by_name: string | null;
	not_yet_note: string | null;
	approved_at: string | null;
	approved_by_name: string | null;
	approved_by_email: string | null;
	approval_method: LaunchApprovalMethod | null;
	approval_wording: string | null;
	recorded_reason: string | null;
	replaced_at: string | null;
};

export const LAUNCH_APPROVAL_COLUMNS =
	'id, version, requested_at, approver_name, approver_email, link_sent_at, link_expires_at, status, closed_reason, closed_at, not_yet_at, not_yet_by_name, not_yet_note, approved_at, approved_by_name, approved_by_email, approval_method, approval_wording, recorded_reason, replaced_at';

/** The open request or the standing approval: the one the client acts on or sees as a receipt. */
export function currentLaunchApproval(requests: LaunchApprovalRequest[]) {
	return (
		requests.find(
			(request) =>
				request.status === 'open' || (request.status === 'approved' && !request.replaced_at)
		) ?? null
	);
}

/** How the approval was given, in words. */
export const LAUNCH_APPROVAL_METHOD_LABEL: Record<LaunchApprovalMethod, string> = {
	signed_in: 'on the Setup page',
	link: 'through the emailed link',
	recorded: 'recorded by Uplift'
};

/** What ended a request, in Jafar's words. */
export function launchApprovalOutcome(request: LaunchApprovalRequest): string {
	if (request.status === 'approved')
		return request.replaced_at ? 'Approved — replaced by a newer preview' : 'Approved';
	if (request.status === 'cancelled')
		return request.closed_reason === 'corrections_sent'
			? 'Cancelled — they sent corrections'
			: 'Cancelled — a newer preview was released';
	return request.not_yet_at ? 'Said not yet' : 'Waiting for approval';
}

/** What the private link page shows. */
export type LaunchLinkDocument = {
	business_name: string;
	version: number;
	approver_name: string;
	status: 'open' | 'approved';
	wording: string;
	approved_at: string | null;
	not_yet_at: string | null;
	cards: { id: string; title: string; summary: string; link: string | null }[];
};
