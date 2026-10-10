/**
 * Whose bell a notification query reads (Jafar business management D3a): a teammate's own alerts, or for Jafar
 * (no member id) everything not addressed to a teammate. Every read and read-state change goes through it.
 */
export function forViewer<
	Q extends {
		eq(column: 'recipient_member_id', value: string): Q;
		is(column: 'recipient_member_id', value: null): Q;
	}
>(query: Q, memberId: string | null): Q {
	return memberId
		? query.eq('recipient_member_id', memberId)
		: query.is('recipient_member_id', null);
}
