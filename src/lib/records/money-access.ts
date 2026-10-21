// Whether this person may see cost and profit on a record not saved yet, and the business's target margin to
// measure a projected profit against. One small read for the whole session; permissions rarely change.
export type MoneyAccess = {
	can_see_cost: { job: boolean; quote: boolean; invoice: boolean };
	target_margin_basis_points: number | null;
};

export const moneyAccessKey = ['records', 'money-access'] as const;

export async function fetchMoneyAccess(): Promise<MoneyAccess> {
	const response = await fetch('/api/records/money-access');
	if (!response.ok) throw new Error('Cost access could not be checked.');
	return (await response.json()) as MoneyAccess;
}
